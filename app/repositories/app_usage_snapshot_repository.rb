module VCAP::CloudController
  module Repositories
    class AppUsageSnapshotRepository
      # Populates an existing snapshot record with actual data.
      # The snapshot was created by the controller to establish the job link
      # (following the pattern from CreateBindingAsyncJob).
      #
      # @param snapshot [AppUsageSnapshot] The pre-created snapshot record to populate
      def populate_snapshot!(snapshot)
        start_time = Time.now

        AppUsageSnapshot.db.transaction do
          # Get checkpoint - the most recent usage event at this moment
          checkpoint_event = AppUsageEvent.order(Sequel.desc(:id)).first
          checkpoint_event_id = checkpoint_event&.id
          checkpoint_event_created_at = checkpoint_event&.created_at

          # Build base query with joins (for count queries) and full query with selects (for streaming)
          base_query = fetch_running_processes_base_query
          process_query = fetch_running_processes_query

          # Calculate summary counts using SQL aggregates (no full load into memory)
          # Use base query with table-qualified column names for counts
          process_count = base_query.count
          org_count = base_query.select(:"#{Organization.table_name}__guid").exclude("#{Organization.table_name}__guid": nil).distinct.count
          space_count = base_query.select(:"#{Space.table_name}__guid").exclude("#{Space.table_name}__guid": nil).distinct.count

          # Update snapshot with actual data
          snapshot.update(
            checkpoint_event_id: checkpoint_event_id,
            checkpoint_event_created_at: checkpoint_event_created_at,
            process_count: process_count,
            organization_count: org_count,
            space_count: space_count
          )

          # Stream and batch insert details using cursor-based iteration.
          # This avoids loading all rows into memory at once, which could OOM
          # on large foundations (1M+ processes = gigabytes of RAM).
          insert_snapshot_details_streaming(snapshot.id, process_query)

          # Mark complete
          # NOTE: We call Time.now.utc multiple times (for created_at and completed_at).
          # In theory, clock adjustments could cause completed_at < created_at, but this
          # is extremely rare and doesn't affect functionality. The timestamps are for
          # informational purposes, not ordering guarantees.
          snapshot.update(completed_at: Time.now.utc)
        end

        # Reload to ensure in-memory object reflects DB state after transaction
        snapshot.reload

        # Metrics recorded after successful transaction commit
        duration = Time.now - start_time
        logger.info("Snapshot #{snapshot.guid} created: #{snapshot.process_count} processes in #{duration.round(2)}s")
        prometheus.update_histogram_metric(:cc_app_usage_snapshot_generation_duration_seconds, duration)
        prometheus.update_gauge_metric(:cc_app_usage_snapshot_process_count, snapshot.process_count)

        snapshot
      rescue StandardError => e
        logger.error("Snapshot generation failed: #{e.message}")
        prometheus.increment_counter_metric(:cc_app_usage_snapshot_generation_failures_total)
        raise
      end

      private

      # Base query with joins only (no SELECT clause) - used for count operations
      def fetch_running_processes_base_query
        ProcessModel.
          left_join(AppModel.table_name, { guid: :app_guid }, table_alias: :parent_app).
          left_join(Space.table_name, guid: :space_guid).
          left_join(Organization.table_name, id: :organization_id).
          where("#{ProcessModel.table_name}__state": ProcessModel::STARTED).
          exclude("#{ProcessModel.table_name}__type": %w[TASK build]).
          order(:"#{ProcessModel.table_name}__id")
      end

      # Full query with SELECT clause and aliases - used for streaming/iteration
      def fetch_running_processes_query
        fetch_running_processes_base_query.
          select(
            Sequel.as(:"#{Organization.table_name}__guid", :organization_guid),
            Sequel.as(:"#{Space.table_name}__guid", :space_guid),
            Sequel.as(:parent_app__guid, :app_guid),
            Sequel.as(:"#{ProcessModel.table_name}__guid", :process_guid),
            Sequel.as(:"#{ProcessModel.table_name}__type", :process_type),
            Sequel.as(:"#{ProcessModel.table_name}__instances", :instances)
          )
      end

      # Batch size of 1000 is consistent with other bulk operations in this codebase.
      # See: lib/cloud_controller/diego/reporters/instances_stats_reporter.rb
      # This balances memory usage against number of database round-trips.
      BATCH_SIZE = 1000

      def insert_snapshot_details_streaming(snapshot_id, process_query)
        # Use paged_each for cursor-based iteration. This fetches rows in batches
        # from the database without loading everything into Ruby memory at once.
        # Memory profile: O(BATCH_SIZE) instead of O(total_rows)
        batch = []
        process_query.paged_each(rows_per_fetch: BATCH_SIZE) do |row|
          batch << row
          if batch.size >= BATCH_SIZE
            insert_snapshot_batch(snapshot_id, batch)
            batch = []
          end
        end
        # Insert any remaining rows
        insert_snapshot_batch(snapshot_id, batch) unless batch.empty?
      end

      def insert_snapshot_batch(snapshot_id, batch)
        return if batch.empty?

        rows = batch.map do |p|
          {
            snapshot_id: snapshot_id,
            organization_guid: p[:organization_guid],
            space_guid: p[:space_guid],
            app_guid: p[:app_guid],
            process_guid: p[:process_guid],
            process_type: p[:process_type],
            instances: p[:instances]
          }
        end
        AppUsageSnapshotDetail.multi_insert(rows)
      end

      def prometheus
        @prometheus ||= CloudController::DependencyLocator.instance.prometheus_updater
      end

      def logger
        @logger ||= Steno.logger('cc.app_usage_snapshot_repository')
      end
    end
  end
end

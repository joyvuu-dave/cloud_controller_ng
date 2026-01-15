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

        DB.transaction do
          # Get checkpoint - the most recent usage event at this moment
          checkpoint_event = AppUsageEvent.order(Sequel.desc(:id)).first
          checkpoint_event_id = checkpoint_event&.id
          checkpoint_event_created_at = checkpoint_event&.created_at

          # Build query for running processes (with LEFT JOIN for deleted orgs/spaces)
          process_query = fetch_running_processes_query

          # Calculate summary counts using SQL aggregates (no full load into memory)
          process_count = process_query.count
          org_count = process_query.select(:organization_guid).exclude(organization_guid: nil).distinct.count
          space_count = process_query.select(:space_guid).exclude(space_guid: nil).distinct.count

          # Update snapshot with actual data
          snapshot.update(
            checkpoint_event_id: checkpoint_event_id,
            checkpoint_event_created_at: checkpoint_event_created_at,
            process_count: process_count,
            organization_count: org_count,
            space_count: space_count
          )

          # Load and batch insert details
          running_processes = process_query.all
          insert_snapshot_details(snapshot.id, running_processes)

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

      def fetch_running_processes_query
        ProcessModel.
          left_join(AppModel.table_name, { guid: :app_guid }, table_alias: :parent_app).
          left_join(Space.table_name, guid: :space_guid).
          left_join(Organization.table_name, id: :organization_id).
          select(
            :"#{Organization.table_name}__guid".as(:organization_guid),
            :"#{Space.table_name}__guid".as(:space_guid),
            :parent_app__guid.as(:app_guid),
            :"#{ProcessModel.table_name}__guid".as(:process_guid),
            :"#{ProcessModel.table_name}__type".as(:process_type),
            :"#{ProcessModel.table_name}__instances".as(:instances)
          ).
          where("#{ProcessModel.table_name}__state": ProcessModel::STARTED).
          exclude("#{ProcessModel.table_name}__type": %w[TASK build]).
          order(:"#{ProcessModel.table_name}__id")
      end

      def insert_snapshot_details(snapshot_id, processes)
        # Batch size of 1000 is consistent with other bulk operations in this codebase.
        # See: lib/cloud_controller/diego/reporters/instances_stats_reporter.rb
        # This balances memory usage against number of database round-trips.
        processes.each_slice(1000) do |batch|
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

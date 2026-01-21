require 'oj'

module VCAP::CloudController
  module Repositories
    class AppUsageSnapshotRepository
      BATCH_SIZE = 1000

      # Populates an existing snapshot record with actual data.
      # The snapshot was created by the controller to establish the job link
      # (following the pattern from CreateBindingAsyncJob).
      #
      # Creates one AppUsageSnapshotSpace record per space containing running processes,
      # with embedded JSON listing all processes in that space.
      #
      # @param snapshot [AppUsageSnapshot] The pre-created snapshot record to populate
      def populate_snapshot!(snapshot)
        start_time = Time.now

        total_instances = 0
        org_guids = Set.new
        space_count = 0

        AppUsageSnapshot.db.transaction do
          # Get checkpoint - the most recent usage event at this moment
          checkpoint_event = AppUsageEvent.order(Sequel.desc(:id)).first
          checkpoint_event_id = checkpoint_event&.id
          checkpoint_event_created_at = checkpoint_event&.created_at

          # Query all running processes with space/org info
          processes_by_space = fetch_processes_grouped_by_space

          # Build and insert space records in batches
          space_records = []
          processes_by_space.each do |space_guid, space_data|
            space_count += 1
            org_guids << space_data[:organization_guid]
            space_instance_count = space_data[:processes].sum { |p| p[:instances] }
            total_instances += space_instance_count

            space_records << {
              app_usage_snapshot_id: snapshot.id,
              space_guid: space_guid,
              organization_guid: space_data[:organization_guid],
              instance_count: space_instance_count,
              processes: Oj.dump(space_data[:processes], mode: :compat)
            }

            # Batch insert when we hit the batch size
            if space_records.size >= BATCH_SIZE
              AppUsageSnapshotSpace.dataset.multi_insert(space_records)
              space_records = []
            end
          end

          # Insert any remaining records
          AppUsageSnapshotSpace.dataset.multi_insert(space_records) if space_records.any?

          # Update snapshot with totals and mark complete
          snapshot.update(
            checkpoint_event_id: checkpoint_event_id,
            checkpoint_event_created_at: checkpoint_event_created_at,
            instance_count: total_instances,
            organization_count: org_guids.size,
            space_count: space_count,
            completed_at: Time.now.utc
          )
        end

        # Reload to ensure in-memory object reflects DB state after transaction
        snapshot.reload

        # Metrics recorded after successful transaction commit
        duration = Time.now - start_time
        logger.info("Snapshot #{snapshot.guid} created: #{snapshot.instance_count} instances across #{snapshot.space_count} spaces in #{duration.round(2)}s")
        prometheus.update_histogram_metric(:cc_app_usage_snapshot_generation_duration_seconds, duration)
        prometheus.update_gauge_metric(:cc_app_usage_snapshot_instance_count, snapshot.instance_count)

        snapshot
      rescue StandardError => e
        logger.error("Snapshot generation failed: #{e.message}")
        prometheus.increment_counter_metric(:cc_app_usage_snapshot_generation_failures_total)
        raise
      end

      private

      # Query running processes and group by space_guid
      # Returns a hash: { space_guid => { organization_guid: ..., processes: [...] } }
      def fetch_processes_grouped_by_space
        result = {}

        # Query running processes with space/org info
        query = ProcessModel.
                left_join(AppModel.table_name, { guid: :app_guid }, table_alias: :parent_app).
                left_join(Space.table_name, guid: :space_guid).
                left_join(Organization.table_name, id: :organization_id).
                where("#{ProcessModel.table_name}__state": ProcessModel::STARTED).
                exclude("#{ProcessModel.table_name}__type": %w[TASK build]).
                select(
                  Sequel.as(:"#{ProcessModel.table_name}__app_guid", :app_guid),
                  Sequel.as(:"#{ProcessModel.table_name}__type", :process_type),
                  Sequel.as(:"#{ProcessModel.table_name}__instances", :instances),
                  Sequel.as(:"#{Space.table_name}__guid", :space_guid),
                  Sequel.as(:"#{Organization.table_name}__guid", :organization_guid)
                )

        query.paged_each(rows_per_fetch: BATCH_SIZE) do |row|
          space_guid = row[:space_guid]
          next if space_guid.nil?

          result[space_guid] ||= {
            organization_guid: row[:organization_guid],
            processes: []
          }

          result[space_guid][:processes] << {
            app_guid: row[:app_guid],
            process_type: row[:process_type],
            instances: row[:instances]
          }
        end

        result
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

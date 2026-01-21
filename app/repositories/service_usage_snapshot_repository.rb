require 'oj'

module VCAP::CloudController
  module Repositories
    class ServiceUsageSnapshotRepository
      BATCH_SIZE = 1000

      # Populates an existing snapshot record with actual data.
      # The snapshot was created by the controller to establish the job link
      # (following the pattern from CreateBindingAsyncJob).
      #
      # Creates one ServiceUsageSnapshotSpace record per space containing service instances,
      # with embedded JSON listing all service instances in that space.
      #
      # @param snapshot [ServiceUsageSnapshot] The pre-created snapshot record to populate
      def populate_snapshot!(snapshot)
        start_time = Time.now

        total_service_instances = 0
        org_guids = Set.new
        space_count = 0

        ServiceUsageSnapshot.db.transaction do
          # Get checkpoint - the most recent usage event at this moment
          checkpoint_event = ServiceUsageEvent.order(Sequel.desc(:id)).first
          checkpoint_event_id = checkpoint_event&.id
          checkpoint_event_created_at = checkpoint_event&.created_at

          # Query all service instances with space/org info
          instances_by_space = fetch_service_instances_grouped_by_space

          # Build and insert space records in batches
          space_records = []
          instances_by_space.each do |space_guid, space_data|
            space_count += 1
            org_guids << space_data[:organization_guid]
            space_instance_count = space_data[:service_instances].size
            total_service_instances += space_instance_count

            space_records << {
              service_usage_snapshot_id: snapshot.id,
              space_guid: space_guid,
              organization_guid: space_data[:organization_guid],
              service_instance_count: space_instance_count,
              service_instances: Oj.dump(space_data[:service_instances], mode: :compat)
            }

            # Batch insert when we hit the batch size
            if space_records.size >= BATCH_SIZE
              ServiceUsageSnapshotSpace.dataset.multi_insert(space_records)
              space_records = []
            end
          end

          # Insert any remaining records
          ServiceUsageSnapshotSpace.dataset.multi_insert(space_records) if space_records.any?

          # Update snapshot with totals and mark complete
          snapshot.update(
            checkpoint_event_id: checkpoint_event_id,
            checkpoint_event_created_at: checkpoint_event_created_at,
            service_instance_count: total_service_instances,
            organization_count: org_guids.size,
            space_count: space_count,
            completed_at: Time.now.utc
          )
        end

        # Reload to ensure in-memory object reflects DB state after transaction
        snapshot.reload

        # Metrics recorded after successful transaction commit
        duration = Time.now - start_time
        logger.info("Service snapshot #{snapshot.guid} created: " \
                    "#{snapshot.service_instance_count} service instances across #{snapshot.space_count} spaces in #{duration.round(2)}s")
        prometheus.update_histogram_metric(:cc_service_usage_snapshot_generation_duration_seconds, duration)
        prometheus.update_gauge_metric(:cc_service_usage_snapshot_service_instance_count, snapshot.service_instance_count)

        snapshot
      rescue StandardError => e
        logger.error("Service snapshot generation failed: #{e.message}")
        prometheus.increment_counter_metric(:cc_service_usage_snapshot_generation_failures_total)
        raise
      end

      private

      # Query service instances and group by space_guid
      # Returns a hash: { space_guid => { organization_guid: ..., service_instances: [...] } }
      def fetch_service_instances_grouped_by_space
        result = {}

        # Query service instances with space/org info
        query = ServiceInstance.
                left_join(:spaces, id: :service_instances__space_id).
                left_join(:organizations, id: :spaces__organization_id).
                left_join(:service_plans, id: :service_instances__service_plan_id).
                left_join(:services, id: :service_plans__service_id).
                select(
                  Sequel.as(:service_instances__guid, :guid),
                  Sequel.as(:service_instances__name, :name),
                  Sequel.as(:service_instances__is_gateway_service, :is_managed),
                  Sequel.as(:services__label, :service_label),
                  Sequel.as(:service_plans__name, :plan_name),
                  Sequel.as(:spaces__guid, :space_guid),
                  Sequel.as(:organizations__guid, :organization_guid)
                )

        query.paged_each(rows_per_fetch: BATCH_SIZE) do |row|
          space_guid = row[:space_guid]
          next if space_guid.nil?

          result[space_guid] ||= {
            organization_guid: row[:organization_guid],
            service_instances: []
          }

          result[space_guid][:service_instances] << {
            guid: row[:guid],
            name: row[:name],
            type: row[:is_managed] ? 'managed' : 'user_provided',
            service_label: row[:service_label],
            plan_name: row[:plan_name]
          }
        end

        result
      end

      def prometheus
        @prometheus ||= CloudController::DependencyLocator.instance.prometheus_updater
      end

      def logger
        @logger ||= Steno.logger('cc.service_usage_snapshot_repository')
      end
    end
  end
end

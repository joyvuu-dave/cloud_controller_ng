module VCAP::CloudController
  module Repositories
    class ServiceUsageSnapshotRepository
      # Populates an existing snapshot record with actual data.
      # The snapshot was created by the controller to establish the job link
      # (following the pattern from CreateBindingAsyncJob).
      #
      # @param snapshot [ServiceUsageSnapshot] The pre-created snapshot record to populate
      def populate_snapshot!(snapshot)
        start_time = Time.now

        DB.transaction do
          # Get checkpoint - the most recent usage event at this moment
          checkpoint_event = ServiceUsageEvent.order(Sequel.desc(:id)).first
          checkpoint_event_id = checkpoint_event&.id || 0
          checkpoint_event_created_at = checkpoint_event&.created_at

          # Build query for service instances (with LEFT JOIN for deleted orgs/spaces and user-provided services)
          service_query = fetch_service_instances_query

          # Calculate summary counts using SQL aggregates (no full load into memory)
          service_instance_count = service_query.count
          org_count = service_query.select(:organization_guid).exclude(organization_guid: nil).distinct.count
          space_count = service_query.select(:space_guid).exclude(space_guid: nil).distinct.count

          # Update snapshot with actual data
          snapshot.update(
            checkpoint_event_id: checkpoint_event_id,
            checkpoint_event_created_at: checkpoint_event_created_at,
            service_instance_count: service_instance_count,
            organization_count: org_count,
            space_count: space_count
          )

          # Load and batch insert details
          service_instances = service_query.all
          insert_snapshot_details(snapshot.id, service_instances)

          # Mark complete
          # Note: We call Time.now.utc multiple times (for created_at and completed_at).
          # In theory, clock adjustments could cause completed_at < created_at, but this
          # is extremely rare and doesn't affect functionality. The timestamps are for
          # informational purposes, not ordering guarantees.
          snapshot.update(completed_at: Time.now.utc)
        end

        # Metrics recorded after successful transaction commit
        duration = Time.now - start_time
        logger.info("Service snapshot #{snapshot.guid} created: #{snapshot.service_instance_count} service instances in #{duration.round(2)}s")
        prometheus.update_histogram_metric(:cc_service_usage_snapshot_generation_duration_seconds, duration)
        prometheus.update_gauge_metric(:cc_service_usage_snapshot_service_instance_count, snapshot.service_instance_count)

        snapshot
      rescue StandardError => e
        logger.error("Service snapshot generation failed: #{e.message}")
        prometheus.increment_counter_metric(:cc_service_usage_snapshot_generation_failures_total)
        raise
      end

      private

      def fetch_service_instances_query
        # Mirror the query from ServiceUsageEventRepository#purge_and_reseed_service_instances!
        # Use LEFT JOIN for service_plans, services, and service_brokers because user-provided services don't have those relations
        # Use LEFT JOIN for spaces and organizations to handle soft-deleted entities
        ServiceInstance.
          left_join(:spaces, id: :service_instances__space_id).
          left_join(:organizations, id: :spaces__organization_id).
          left_join(:service_plans, id: :service_instances__service_plan_id).
          left_join(:services, id: :service_plans__service_id).
          left_join(:service_brokers, id: :services__service_broker_id).
          select(
            :organizations__guid___organization_guid,
            :spaces__guid___space_guid,
            :service_instances__guid___service_instance_guid,
            :service_instances__name___service_instance_name,
            Sequel.case({ { Sequel.qualify(:service_instances, :is_gateway_service) => false } => 'user_provided' }, 'managed_service_instance').as(:service_instance_type),
            :service_plans__guid___service_plan_guid,
            :service_plans__name___service_plan_name,
            :services__guid___service_offering_guid,
            :services__label___service_offering_name,
            :service_brokers__guid___service_broker_guid,
            :service_brokers__name___service_broker_name
          ).
          order(:service_instances__id)
      end

      def insert_snapshot_details(snapshot_id, service_instances)
        # Batch size of 1000 is consistent with other bulk operations in this codebase.
        # See: lib/cloud_controller/diego/reporters/instances_stats_reporter.rb
        # This balances memory usage against number of database round-trips.
        service_instances.each_slice(1000) do |batch|
          rows = batch.map do |si|
            {
              snapshot_id: snapshot_id,
              organization_guid: si[:organization_guid],
              space_guid: si[:space_guid],
              service_instance_guid: si[:service_instance_guid],
              service_instance_name: si[:service_instance_name],
              service_instance_type: si[:service_instance_type],
              service_plan_guid: si[:service_plan_guid],
              service_plan_name: si[:service_plan_name],
              service_offering_guid: si[:service_offering_guid],
              service_offering_name: si[:service_offering_name],
              service_broker_guid: si[:service_broker_guid],
              service_broker_name: si[:service_broker_name]
            }
          end
          ServiceUsageSnapshotDetail.multi_insert(rows)
        end
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

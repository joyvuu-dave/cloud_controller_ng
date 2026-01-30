require 'oj'

module VCAP::CloudController
  module Repositories
    class ServiceUsageSnapshotRepository
      BATCH_SIZE = 1000
      CHUNK_LIMIT = 100

      # Populates an existing snapshot record with actual data.
      # The snapshot was created by the controller to establish the job link
      # (following the pattern from CreateBindingAsyncJob).
      #
      # Creates one ServiceUsageSnapshotChunk per 100 service instances per space.
      # If a space has more than 100 service instances, it gets multiple chunks.
      #
      # This implementation uses streaming (paged_each) to avoid loading all
      # service instances into memory at once, making it suitable for very large datasets.
      #
      # @param snapshot [ServiceUsageSnapshot] The pre-created snapshot record to populate
      def populate_snapshot!(snapshot)
        start_time = Time.now

        generator = ChunkGenerator.new(snapshot, CHUNK_LIMIT, logger)

        ServiceUsageSnapshot.db.transaction do
          # Get checkpoint - the most recent usage event at this moment
          checkpoint_event = ServiceUsageEvent.order(Sequel.desc(:id)).first

          # Stream service instances and generate chunks
          generator.generate_from_stream(build_service_instance_query, snapshot.last_processed_service_instance_id)

          # Update snapshot with totals and mark complete
          snapshot.update(
            checkpoint_event_id: checkpoint_event&.id,
            checkpoint_event_created_at: checkpoint_event&.created_at,
            service_instance_count: generator.total_service_instances,
            organization_count: generator.org_guids.size,
            space_count: generator.space_guids.size,
            chunk_count: generator.chunk_count,
            last_processed_service_instance_id: nil, # Clear resumability marker on completion
            completed_at: Time.now.utc
          )
        end

        # Reload to ensure in-memory object reflects DB state after transaction
        snapshot.reload

        # Metrics recorded after successful transaction commit
        duration = Time.now - start_time
        logger.info("Service snapshot #{snapshot.guid} created: " \
                    "#{snapshot.service_instance_count} service instances, #{snapshot.chunk_count} chunks in #{duration.round(2)}s")
        prometheus.update_histogram_metric(:cc_service_usage_snapshot_generation_duration_seconds, duration)
        prometheus.update_gauge_metric(:cc_service_usage_snapshot_service_instance_count, snapshot.service_instance_count)

        snapshot
      rescue StandardError => e
        logger.error("Service snapshot generation failed: #{e.message}")
        prometheus.increment_counter_metric(:cc_service_usage_snapshot_generation_failures_total)
        raise
      end

      private

      def build_service_instance_query
        # Query service instances with space/org info, ordered by space then id
        # for proper chunking.
        ServiceInstance.
          left_join(:spaces, id: :service_instances__space_id).
          left_join(:organizations, id: :spaces__organization_id).
          left_join(:service_plans, id: :service_instances__service_plan_id).
          left_join(:services, id: :service_plans__service_id).
          order(Sequel.qualify(:spaces, :guid), Sequel.qualify(:service_instances, :id)).
          select(
            Sequel.as(:service_instances__id, :service_instance_id),
            Sequel.as(:service_instances__guid, :guid),
            Sequel.as(:service_instances__name, :name),
            Sequel.as(:service_instances__is_gateway_service, :is_managed),
            Sequel.as(:services__label, :service_label),
            Sequel.as(:service_plans__name, :plan_name),
            Sequel.as(:spaces__guid, :space_guid),
            Sequel.as(:organizations__guid, :organization_guid)
          )
      end

      def prometheus
        @prometheus ||= CloudController::DependencyLocator.instance.prometheus_updater
      end

      def logger
        @logger ||= Steno.logger('cc.service_usage_snapshot_repository')
      end

      # Internal class to handle chunk generation with bounded memory
      class ChunkGenerator
        attr_reader :total_service_instances, :chunk_count, :org_guids, :space_guids

        def initialize(snapshot, chunk_limit, logger)
          @snapshot = snapshot
          @chunk_limit = chunk_limit
          @logger = logger

          @total_service_instances = 0
          @chunk_count = 0
          @org_guids = Set.new
          @space_guids = Set.new

          @current_space_guid = nil
          @current_org_guid = nil
          @current_chunk_index = 0
          @current_chunk_instances = []
          @pending_chunks = []
        end

        def generate_from_stream(query, resume_from_id = nil)
          # Apply resumability filter if resuming from a previous run
          query = query.where { Sequel.qualify(:service_instances, :id) > resume_from_id } if resume_from_id

          query.paged_each(rows_per_fetch: BATCH_SIZE) do |row|
            process_row(row)
          end

          # Flush any remaining data
          flush_current_chunk if @current_chunk_instances.any?
          flush_pending_chunks
        end

        private

        def process_row(row)
          space_guid = row[:space_guid]
          return if space_guid.nil?

          org_guid = row[:organization_guid]

          # Detect space change - flush current chunk and reset
          if space_guid != @current_space_guid
            flush_current_chunk if @current_chunk_instances.any?
            @current_space_guid = space_guid
            @current_org_guid = org_guid
            @current_chunk_index = 0
            @current_chunk_instances = []
          end

          # Track totals
          @org_guids << org_guid
          @space_guids << space_guid
          @total_service_instances += 1

          # Add service instance to current chunk
          @current_chunk_instances << {
            guid: row[:guid],
            name: row[:name],
            type: row[:is_managed] ? 'managed' : 'user_provided',
            service_label: row[:service_label],
            plan_name: row[:plan_name]
          }

          # Update resumability marker periodically
          update_resumability_marker(row[:service_instance_id]) if (@total_service_instances % BATCH_SIZE).zero?

          # Check if chunk is full
          return unless @current_chunk_instances.size >= @chunk_limit

          flush_current_chunk
          @current_chunk_index += 1
          @current_chunk_instances = []
        end

        def flush_current_chunk
          return if @current_chunk_instances.empty?

          @pending_chunks << {
            service_usage_snapshot_id: @snapshot.id,
            organization_guid: @current_org_guid,
            space_guid: @current_space_guid,
            chunk_index: @current_chunk_index,
            service_instance_count: @current_chunk_instances.size,
            service_instances: Oj.dump(@current_chunk_instances, mode: :compat)
          }
          @chunk_count += 1

          # Batch insert when we have enough pending chunks
          flush_pending_chunks if @pending_chunks.size >= BATCH_SIZE
        end

        def flush_pending_chunks
          return if @pending_chunks.empty?

          ServiceUsageSnapshotChunk.dataset.multi_insert(@pending_chunks)
          @pending_chunks = []
        end

        def update_resumability_marker(service_instance_id)
          # Update the snapshot with the last processed ID for crash recovery
          # This is done outside the main transaction to allow recovery
          @snapshot.this.update(last_processed_service_instance_id: service_instance_id)
        end
      end
    end
  end
end

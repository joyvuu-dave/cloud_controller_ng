require 'oj'

module VCAP::CloudController
  module Repositories
    class AppUsageSnapshotRepository
      BATCH_SIZE = 1000
      CHUNK_LIMIT = 100

      # Populates an existing snapshot record with actual data.
      # The snapshot was created by the controller to establish the job link
      # (following the pattern from CreateBindingAsyncJob).
      #
      # Creates one AppUsageSnapshotChunk per 100 processes per space.
      # If a space has more than 100 processes, it gets multiple chunks.
      #
      # This implementation uses streaming (paged_each) to avoid loading all
      # processes into memory at once, making it suitable for very large datasets.
      #
      # @param snapshot [AppUsageSnapshot] The pre-created snapshot record to populate
      def populate_snapshot!(snapshot)
        start_time = Time.now

        generator = ChunkGenerator.new(snapshot, CHUNK_LIMIT, logger)

        AppUsageSnapshot.db.transaction do
          # Get checkpoint - the most recent usage event at this moment
          checkpoint_event = AppUsageEvent.order(Sequel.desc(:id)).first

          # Stream processes and generate chunks
          generator.generate_from_stream(build_process_query, snapshot.last_processed_process_id)

          # Update snapshot with totals and mark complete
          snapshot.update(
            checkpoint_event_id: checkpoint_event&.id,
            checkpoint_event_created_at: checkpoint_event&.created_at,
            instance_count: generator.total_instances,
            organization_count: generator.org_guids.size,
            space_count: generator.space_guids.size,
            process_count: generator.total_processes,
            chunk_count: generator.chunk_count,
            last_processed_process_id: nil, # Clear resumability marker on completion
            completed_at: Time.now.utc
          )
        end

        # Reload to ensure in-memory object reflects DB state after transaction
        snapshot.reload

        # Metrics recorded after successful transaction commit
        duration = Time.now - start_time
        logger.info("Snapshot #{snapshot.guid} created: #{snapshot.instance_count} instances, " \
                    "#{snapshot.process_count} processes, #{snapshot.chunk_count} chunks in #{duration.round(2)}s")
        prometheus.update_histogram_metric(:cc_app_usage_snapshot_generation_duration_seconds, duration)
        prometheus.update_gauge_metric(:cc_app_usage_snapshot_instance_count, snapshot.instance_count)

        snapshot
      rescue StandardError => e
        logger.error("Snapshot generation failed: #{e.message}")
        prometheus.increment_counter_metric(:cc_app_usage_snapshot_generation_failures_total)
        raise
      end

      private

      def build_process_query
        # Query running processes with space/org info, ordered by space then id
        # for proper chunking. Using the composite index on (state, id).
        ProcessModel.
          left_join(AppModel.table_name, { guid: :app_guid }, table_alias: :parent_app).
          left_join(Space.table_name, guid: :space_guid).
          left_join(Organization.table_name, id: :organization_id).
          where("#{ProcessModel.table_name}__state": ProcessModel::STARTED).
          exclude("#{ProcessModel.table_name}__type": %w[TASK build]).
          order(Sequel.qualify(Space.table_name, :guid), Sequel.qualify(ProcessModel.table_name, :id)).
          select(
            Sequel.as(:"#{ProcessModel.table_name}__id", :process_id),
            Sequel.as(:"#{ProcessModel.table_name}__app_guid", :app_guid),
            Sequel.as(:"#{ProcessModel.table_name}__type", :process_type),
            Sequel.as(:"#{ProcessModel.table_name}__instances", :instances),
            Sequel.as(:"#{Space.table_name}__guid", :space_guid),
            Sequel.as(:"#{Organization.table_name}__guid", :organization_guid)
          )
      end

      def prometheus
        @prometheus ||= CloudController::DependencyLocator.instance.prometheus_updater
      end

      def logger
        @logger ||= Steno.logger('cc.app_usage_snapshot_repository')
      end

      # Internal class to handle chunk generation with bounded memory
      class ChunkGenerator
        attr_reader :total_instances, :total_processes, :chunk_count, :org_guids, :space_guids

        def initialize(snapshot, chunk_limit, logger)
          @snapshot = snapshot
          @chunk_limit = chunk_limit
          @logger = logger

          @total_instances = 0
          @total_processes = 0
          @chunk_count = 0
          @org_guids = Set.new
          @space_guids = Set.new

          @current_space_guid = nil
          @current_org_guid = nil
          @current_chunk_index = 0
          @current_chunk_processes = []
          @current_chunk_instances = 0
          @pending_chunks = []
        end

        def generate_from_stream(query, resume_from_process_id = nil)
          # Apply resumability filter if resuming from a previous run
          query = query.where { Sequel.qualify(ProcessModel.table_name, :id) > resume_from_process_id } if resume_from_process_id

          query.paged_each(rows_per_fetch: BATCH_SIZE) do |row|
            process_row(row)
          end

          # Flush any remaining data
          flush_current_chunk if @current_chunk_processes.any?
          flush_pending_chunks
        end

        private

        def process_row(row)
          space_guid = row[:space_guid]
          return if space_guid.nil?

          org_guid = row[:organization_guid]

          # Detect space change - flush current chunk and reset
          if space_guid != @current_space_guid
            flush_current_chunk if @current_chunk_processes.any?
            @current_space_guid = space_guid
            @current_org_guid = org_guid
            @current_chunk_index = 0
            @current_chunk_processes = []
            @current_chunk_instances = 0
          end

          # Track totals
          @org_guids << org_guid
          @space_guids << space_guid
          @total_processes += 1
          @total_instances += row[:instances]

          # Add process to current chunk
          @current_chunk_processes << {
            app_guid: row[:app_guid],
            process_type: row[:process_type],
            instances: row[:instances]
          }
          @current_chunk_instances += row[:instances]

          # Update resumability marker periodically
          update_resumability_marker(row[:process_id]) if (@total_processes % BATCH_SIZE).zero?

          # Check if chunk is full
          return unless @current_chunk_processes.size >= @chunk_limit

          flush_current_chunk
          @current_chunk_index += 1
          @current_chunk_processes = []
          @current_chunk_instances = 0
        end

        def flush_current_chunk
          return if @current_chunk_processes.empty?

          @pending_chunks << {
            app_usage_snapshot_id: @snapshot.id,
            organization_guid: @current_org_guid,
            space_guid: @current_space_guid,
            chunk_index: @current_chunk_index,
            process_count: @current_chunk_processes.size,
            instance_count: @current_chunk_instances,
            processes: Oj.dump(@current_chunk_processes, mode: :compat)
          }
          @chunk_count += 1

          # Batch insert when we have enough pending chunks
          flush_pending_chunks if @pending_chunks.size >= BATCH_SIZE
        end

        def flush_pending_chunks
          return if @pending_chunks.empty?

          AppUsageSnapshotChunk.dataset.multi_insert(@pending_chunks)
          @pending_chunks = []
        end

        def update_resumability_marker(process_id)
          # Update the snapshot with the last processed ID for crash recovery
          # This is done outside the main transaction to allow recovery
          @snapshot.this.update(last_processed_process_id: process_id)
        end
      end
    end
  end
end

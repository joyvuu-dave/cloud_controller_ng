module VCAP::CloudController
  module Jobs
    module Runtime
      class AppUsageSnapshotGeneratorJob < VCAP::CloudController::Jobs::CCJob
        attr_reader :resource_guid

        # Following the pattern from CreateBindingAsyncJob (app/jobs/v3/create_binding_async_job.rb):
        # The resource_guid must be set in the constructor so that PollableJobWrapper.before_enqueue
        # can read it when creating the PollableJobModel record.
        # Setting it in perform() is too late - the PollableJobModel already exists by then.
        def initialize(snapshot_guid)
          @resource_guid = snapshot_guid
        end

        def perform
          logger = Steno.logger('cc.background.app-usage-snapshot-generator')
          logger.info("Starting usage snapshot generation for snapshot #{@resource_guid}")

          snapshot = AppUsageSnapshot.first(guid: @resource_guid)
          raise "Snapshot not found: #{@resource_guid}" unless snapshot

          repository = Repositories::AppUsageSnapshotRepository.new
          repository.populate_snapshot!(snapshot)

          logger.info("Usage snapshot #{snapshot.guid} completed: #{snapshot.process_count} processes")
        rescue StandardError => e
          logger.error("Usage snapshot generation failed: #{e.message}\n#{e.backtrace.join("\n")}")
          raise
        end

        def job_name_in_configuration
          :app_usage_snapshot_generator
        end

        def max_attempts
          1
        end

        def resource_type
          'app_usage_snapshot'
        end

        def display_name
          'app_usage_snapshot.generate'
        end
      end
    end
  end
end

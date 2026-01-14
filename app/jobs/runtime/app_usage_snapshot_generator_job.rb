module VCAP::CloudController
  module Jobs
    module Runtime
      class AppUsageSnapshotGeneratorJob < VCAP::CloudController::Jobs::CCJob
        attr_reader :resource_guid

        def initialize
          @resource_guid = nil
        end

        def perform
          logger = Steno.logger('cc.background.app-usage-snapshot-generator')
          logger.info('Starting usage snapshot generation')

          repository = Repositories::AppUsageSnapshotRepository.new
          snapshot = repository.generate_snapshot!

          # Store for PollableJobModel linking
          @resource_guid = snapshot.guid

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

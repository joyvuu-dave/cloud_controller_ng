module VCAP::CloudController
  module Jobs
    module Runtime
      class ServiceUsageSnapshotGeneratorJob < VCAP::CloudController::Jobs::CCJob
        attr_reader :resource_guid

        def initialize
          @resource_guid = nil
        end

        def perform
          logger = Steno.logger('cc.background.service-usage-snapshot-generator')
          logger.info('Starting service usage snapshot generation')

          repository = Repositories::ServiceUsageSnapshotRepository.new
          snapshot = repository.generate_snapshot!

          # Store for PollableJobModel linking
          @resource_guid = snapshot.guid

          logger.info("Service usage snapshot #{snapshot.guid} completed: #{snapshot.service_instance_count} service instances")
        rescue StandardError => e
          logger.error("Service usage snapshot generation failed: #{e.message}\n#{e.backtrace.join("\n")}")
          raise
        end

        def job_name_in_configuration
          :service_usage_snapshot_generator
        end

        def max_attempts
          1
        end

        def resource_type
          'service_usage_snapshot'
        end

        def display_name
          'service_usage_snapshot.generate'
        end
      end
    end
  end
end

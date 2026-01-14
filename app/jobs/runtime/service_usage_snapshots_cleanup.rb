module VCAP::CloudController
  module Jobs
    module Runtime
      class ServiceUsageSnapshotsCleanup < VCAP::CloudController::Jobs::CCJob
        attr_accessor :cutoff_age_in_days

        def initialize(cutoff_age_in_days)
          @cutoff_age_in_days = cutoff_age_in_days
        end

        def perform
          logger = Steno.logger('cc.background.service-usage-snapshots-cleanup')
          logger.info("Cleaning up service usage snapshots older than #{cutoff_age_in_days} days")

          cutoff_time = Time.now.utc - cutoff_age_in_days.days
          old_snapshots = ServiceUsageSnapshot.where(
            Sequel.lit('created_at < ? AND completed_at IS NOT NULL', cutoff_time)
          )

          count = old_snapshots.count
          old_snapshots.delete

          logger.info("Deleted #{count} service usage snapshots")
          prometheus.update_gauge_metric(:cc_service_usage_snapshots_cleaned_up_total, count)
        end

        def job_name_in_configuration
          :service_usage_snapshots_cleanup
        end

        def max_attempts
          1
        end

        private

        def prometheus
          @prometheus ||= CloudController::DependencyLocator.instance.prometheus_updater
        end
      end
    end
  end
end

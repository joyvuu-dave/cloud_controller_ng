module VCAP::CloudController
  module Jobs
    module Runtime
      class AppUsageSnapshotCleanup < VCAP::CloudController::Jobs::CCJob
        attr_accessor :cutoff_age_in_days

        def initialize(cutoff_age_in_days)
          @cutoff_age_in_days = cutoff_age_in_days
        end

        def perform
          logger = Steno.logger('cc.background.app-usage-snapshot-cleanup')
          logger.info("Cleaning up usage snapshots older than #{cutoff_age_in_days} days")

          cutoff_time = Time.now.utc - cutoff_age_in_days.days

          # Delete old COMPLETED snapshots (normal cleanup)
          # These are snapshots that finished successfully and are now past retention period.
          # Criteria: created_at < cutoff AND completed_at IS NOT NULL
          old_completed = AppUsageSnapshot.where(
            Sequel.lit('created_at < ? AND completed_at IS NOT NULL', cutoff_time)
          )

          # Delete STALE in-progress snapshots (failure cleanup)
          # These are snapshots that started but never completed, likely due to:
          # - Job worker crash
          # - Database transaction rollback
          # - Out of memory error
          # - Any other failure during generation
          # We consider a snapshot "stale" if it's been processing for more than 1 hour.
          # Criteria: created_at < 1 hour ago AND completed_at IS NULL
          stale_timeout = Time.now.utc - 1.hour
          stale_in_progress = AppUsageSnapshot.where(
            Sequel.lit('created_at < ? AND completed_at IS NULL', stale_timeout)
          )

          completed_count = old_completed.count
          stale_count = stale_in_progress.count

          # Delete both sets
          old_completed.delete
          stale_in_progress.delete

          total_count = completed_count + stale_count
          logger.info("Deleted #{completed_count} old completed snapshots and #{stale_count} stale in-progress snapshots")
          prometheus.update_gauge_metric(:cc_app_usage_snapshot_cleaned_up_total, total_count)
        end

        def job_name_in_configuration
          :app_usage_snapshot_cleanup
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

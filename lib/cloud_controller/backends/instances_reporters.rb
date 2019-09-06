require 'cloud_controller/diego/reporters/instances_reporter'
require 'cloud_controller/diego/reporters/instances_stats_reporter'

module VCAP::CloudController
  class InstancesReporters
    def number_of_starting_and_running_instances_for_process(app)
      raise CloudController::Errors::ApiError.new_from_details('InstancesUnavailable') unless app
      diego_reporter(app.organization).number_of_starting_and_running_instances_for_process(app)
    rescue CloudController::Errors::InstancesUnavailable => e
      raise CloudController::Errors::ApiError.new_from_details('InstancesUnavailable', e.to_s)
    end

    def all_instances_for_app(app)
      raise CloudController::Errors::ApiError.new_from_details('InstancesUnavailable') unless app


    diego_reporter(app.organization).all_instances_for_app(app)
    rescue CloudController::Errors::InstancesUnavailable => e
      raise CloudController::Errors::ApiError.new_from_details('InstancesUnavailable', e.to_s)
    end

    def crashed_instances_for_app(app)
      raise CloudController::Errors::ApiError.new_from_details('InstancesUnavailable') unless app

      diego_reporter(app.organization).crashed_instances_for_app(app)
    rescue CloudController::Errors::InstancesUnavailable => e
      raise CloudController::Errors::ApiError.new_from_details('InstancesUnavailable', e.to_s)
    end

    def stats_for_app(app)
      raise CloudController::Errors::ApiError.new_from_details('StatsUnavailable', 'Stats server temporarily unavailable.') unless app

      diego_stats_reporter(app.organization).stats_for_app(app)
    rescue CloudController::Errors::InstancesUnavailable
      raise CloudController::Errors::ApiError.new_from_details('StatsUnavailable', 'Stats server temporarily unavailable.')
    end

    def number_of_starting_and_running_instances_for_processes(apps)
      raise CloudController::Errors::ApiError.new_from_details('InstancesUnavailable') unless apps

      diego_reporter(apps.first.organization).number_of_starting_and_running_instances_for_processes(apps)
    end

    private

    def diego_reporter(org)
      if org.eirini
        Diego::InstancesReporter.new(dependency_locator.opi_instances_client)
      else
        Diego::InstancesReporter.new(dependency_locator.bbs_instances_client)
      end
    end

    def diego_stats_reporter(org)
      log_client = if Config.config.get(:temporary_use_logcache)
                 dependency_locator.traffic_controller_compatible_logcache_client
               else
                 dependency_locator.traffic_controller_client
               end

      instances_client = if org.eirini
        dependency_locator.opi_instances_client
      else
        dependency_locator.bbs_instances_client
      end
      # this is a SPIKE
      Diego::InstancesStatsReporter.new(instances_client, log_client)
    end

    def dependency_locator
      CloudController::DependencyLocator.instance
    end
  end
end

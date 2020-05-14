module VCAP::CloudController
  class ServiceInstanceUsageUpdater
    def update(event)
      case event.state
      when ServiceEvent::CREATED
        add_new_usage(event)
      when ServiceEvent::DELETED
        add_deletion_date(event)
      else
        change_plan_or_rename_usage(event)
      end
    end

    private

    def add_deletion_date(event)
      event_record = running_service_instance_usage(event)
      event_record ? event_record.update!(instance_deleted_at: event.occurred_at) : warn_about(event)
    rescue StandardError => e
      warn_about(event)
      raise e
    end

    def warn_about(event)
      Rails.logger.warn("The event on which it was called: #{event}")
      Rails.logger.warn("Did not find an event corresponding to this service deletion. SERVICE_INSTANCE_GUID: #{event.service_instance_guid}")
    end

    def change_plan_or_rename_usage(event)
      if running_service_instance_usage(event)
        has_plan_changed?(event) ? record_plan_change(event) : rename_usage(event)
      else
        Logger.new(STDERR).warn "UsageNotFound: Service Instance (#{event.service_instance_guid}) was not found. Not Running or Created.\n #{caller.join("\n")})"
      end
    end

    def rename_usage(event)
      running_service_instance_usage(event).update!(service_instance_name: event.service_instance_name)
    end

    def has_plan_changed?(event)
      running_service_instance_usage = running_service_instance_usage(event)

      event.service_plan_guid != running_service_instance_usage.service_plan_guid
    end

    def record_plan_change(event)
      add_new_usage(event) && add_deletion_date(event)
    end

    def add_new_usage(event)
      ServiceInstanceUsage.create!(
        instance_created_at: event.occurred_at,
        org_guid: event.org_guid,
        space_guid: event.space_guid,
        space_name: event.space_name,
        service_instance_name: event.service_instance_name,
        service_instance_guid: event.service_instance_guid,
        service_instance_type: event.service_instance_type,
        service_plan_guid: event.service_plan_guid,
        service_plan_name: event.service_plan_name,
        service_guid: event.service_guid,
        service_label: event.service_label,
      )
    end

    def running_service_instance_usage(event)
      ServiceInstanceUsage.running(event.service_instance_guid)
    end

    class UsageNotFound < StandardError
    end
  end

  class ServiceUsageEvent < Sequel::Model
    plugin :serialization

    export_attributes :state, :org_guid, :space_guid, :space_name,
                      :service_instance_guid, :service_instance_name, :service_instance_type,
                      :service_plan_guid, :service_plan_name,
                      :service_guid, :service_label,
                      :service_broker_name, :service_broker_guid


    def after_create
      ServiceInstanceUsageUpdater.update(self)
    end
  end
end

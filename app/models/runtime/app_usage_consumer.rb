module VCAP::CloudController
  class AppUsageConsumer < Sequel::Model
    plugin :validation_helpers

    many_to_one :last_app_usage_event,
                class: 'VCAP::CloudController::AppUsageEvent'

    def validate
      validates_presence %i[consumer_id last_app_usage_event_id]
      validates_unique :consumer_id
    end

    def before_create
      generate_guid
      super
    end

    def generate_guid
      self.guid ||= SecureRandom.uuid
    end

    export_attributes :consumer_id, :last_app_usage_event_id
  end
end

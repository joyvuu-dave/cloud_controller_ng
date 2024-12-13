module VCAP::CloudController
  class UsageEventConsumer < Sequel::Model
    plugin :validation_helpers

    many_to_one :last_event,
                class: 'VCAP::CloudController::AppUsageEvent'

    def validate
      validates_presence %i[consumer_guid last_event_guid model_name]
      validates_unique :consumer_guid
    end

    def before_create
      generate_guid
      super
    end

    def generate_guid
      self.guid ||= SecureRandom.uuid
    end

    export_attributes :consumer_guid, :last_event_guid, :model_name
  end
end

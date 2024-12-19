module VCAP::CloudController
  class AppUsageConsumer < Sequel::Model
    plugin :validation_helpers

    many_to_one :last_processed_event,
                class: 'VCAP::CloudController::AppUsageEvent',
                key: :last_processed_guid,
                primary_key: :guid

    def validate
      validates_presence %i[consumer_guid last_processed_guid]
      validates_unique :consumer_guid
      validates_max_length 255, :consumer_guid, message: 'must be less than 255 characters'
    end

    def last_processed_guid=(guid)
      self[:last_processed_guid] = if guid.is_a?(String)
                                     guid
                                   else
                                     # If it's an object, it's an AppUsageEvent
                                     guid&.guid
                                   end
    end

    def last_processed_guid
      self[:last_processed_guid]
    end

    def last_processed_event=(event)
      self[:last_processed_guid] = event&.guid
    end

    export_attributes :consumer_guid, :last_processed_guid
  end
end

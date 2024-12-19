module VCAP::CloudController
  class AppUsageConsumer < Sequel::Model
    plugin :validation_helpers

    many_to_one :last_processed_guid,
                class: 'VCAP::CloudController::AppUsageEvent'

    def validate
      validates_presence %i[consumer_guid last_processed_guid]
      validates_unique :consumer_guid
    end

    export_attributes :consumer_guid, :last_processed_guid
  end
end

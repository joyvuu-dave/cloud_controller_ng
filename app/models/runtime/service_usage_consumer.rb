module VCAP::CloudController
    class ServiceUsageConsumer < Sequel::Model
      plugin :validation_helpers
  
      many_to_one :last_processed_guid,
                  class: 'VCAP::CloudController::ServiceUsageEvent'
  
      def validate
        validates_presence %i[consumer_guid last_processed_guid]
        validates_unique :consumer_guid
      end
  
      export_attributes :consumer_guid, :last_processed_guid
    end
  end
  
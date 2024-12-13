module VCAP::CloudController
  class UsageEventConsumersController < RestController::ModelController
    define_attributes do
      attribute :consumer_guid, String, exclude_in: [:update]
      attribute :last_event_guid, String
      attribute :model_name, String, exclude_in: [:update]
    end

    def self.dependencies
      [:usage_event_consumer_repository]
    end

    def inject_dependencies(dependencies)
      super
      @usage_event_consumer_repository = dependencies.fetch(:usage_event_consumer_repository)
    end

    def self.translate_validation_exception(e, attributes)
      case e
      when Sequel::ValidationFailed
        Errors::ApiError.new_from_details('UsageEventConsumerInvalid', e.errors)
      when Sequel::UniqueConstraintViolation
        Errors::ApiError.new_from_details('UsageEventConsumerGuidTaken', attributes['consumer_guid'])
      else
        super
      end
    end

    define_messages
    define_routes
  end
end

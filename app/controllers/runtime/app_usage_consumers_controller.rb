require 'repositories/app_usage_consumer_repository'

module VCAP::CloudController
    class AppUsageConsumersController < RestController::ModelController
      define_attributes do
        attribute :consumer_id, String, required: true
        attribute :last_app_usage_event_id, String, required: true
      end
  
      def self.translate_validation_exception(e, attributes)
        consumer_id_errors = e.errors.on(:consumer_id)
        if consumer_id_errors && consumer_id_errors.include?(:unique)
          Errors::ApiError.new_from_details('ConsumerIdTaken', attributes['consumer_id'])
        else
          Errors::ApiError.new_from_details('InvalidRequest', e.errors.full_messages)
        end
      end
  
      def delete(guid)
        consumer = find_guid_and_validate_access(:delete, guid)
        do_delete(consumer)
      end
  
      def inject_dependencies(dependencies)
        super
        @consumer_repository = dependencies.fetch(:consumer_repository)
      end
  
      private
  
      def after_create(consumer)
        Repositories::AppUsageConsumerEventRepository.record_consumer_created(
          consumer,
          SecurityContext.current_user,
          SecurityContext.current_user_email,
          request_attrs
        )
      end
  
      def after_destroy(consumer)
        Repositories::AppUsageConsumerEventRepository.record_consumer_deleted(
          consumer,
          SecurityContext.current_user,
          SecurityContext.current_user_email
        )
      end
    end
  end
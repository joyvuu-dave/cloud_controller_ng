require 'repositories/usage_event_consumer_repository'

module VCAP::CloudController
  class UsageEventConsumersController < RestController::ModelController
    define_attributes do
      attribute :consumer_guid, String, required: true
      attribute :last_usage_event_guid, String, required: true
      attribute :model_name, String, required: true
    end

    def self.translate_validation_exception(e, attributes)
      consumer_guid_errors = e.errors.on(:consumer_guid)
      if consumer_guid_errors && consumer_guid_errors.include?(:unique)
        Errors::ApiError.new_from_details('ConsumerGuidTaken', attributes['consumer_guid'])
      else
        Errors::ApiError.new_from_details('InvalidRequest', e.errors.full_messages)
      end
    end

    def show(guid)
      usage_event_consumer = find_guid_and_validate_access(:show, guid)
      render status: :ok, json: Presenters::V3::UsageEventConsumerPresenter.new(usage_event_consumer)
    end

    def create
      message = UsageEventConsumerCreateMessage.new(params[:body])
      unprocessable!(message.errors.full_messages) unless message.valid?

      begin
        usage_event_consumer = UsageEventConsumerCreate.create(message)
        Repositories::UsageEventConsumerRepository.record_consumer_created(
          usage_event_consumer,
          SecurityContext.current_user,
          SecurityContext.current_user_email,
          request_attrs
        )
        render status: :created, json: Presenters::V3::UsageEventConsumerPresenter.new(usage_event_consumer)
      rescue UsageEventConsumerCreate::Error => e
        logger.error("Failed to create usage event consumer: #{e.message}")
        logger.error(e.backtrace.join("\n"))
        unprocessable!(e.message)
      rescue StandardError => e
        logger.error("Unexpected error creating usage event consumer: #{e.message}")
        logger.error(e.backtrace.join("\n"))
        raise e
      end
    end

    def update(guid)
      usage_event_consumer = find_guid_and_validate_access(:update, guid)
      message = UsageEventConsumerUpdateMessage.new(params[:body])
      unprocessable!(message.errors.full_messages) unless message.valid?

      usage_event_consumer.db.transaction do
        usage_event_consumer.lock!
        usage_event_consumer.update(last_event_guid: message.last_event_guid)
      end

      render status: :ok, json: Presenters::V3::UsageEventConsumerPresenter.new(usage_event_consumer)
    rescue Sequel::ValidationFailed => e
      unprocessable!(e.message)
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
      Repositories::UsageEventConsumerRepository.record_consumer_created(
        consumer,
        SecurityContext.current_user,
        SecurityContext.current_user_email,
        request_attrs
      )
    end

    def after_destroy(consumer)
      Repositories::UsageEventConsumerRepository.record_consumer_deleted(
        consumer,
        SecurityContext.current_user,
        SecurityContext.current_user_email
      )
    end
  end
end

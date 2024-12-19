require 'messages/service_usage_consumer_create_message'
require 'messages/service_usage_consumers_list_message'
require 'presenters/v3/service_usage_consumer_presenter'

class ServiceUsageConsumersController < ApplicationController
  def index
    dataset = ServiceUsageConsumer.all
    render status: :ok, json: { message: dataset }
  end

  def show
    service_usage_consumer = ServiceUsageConsumer.find(guid: hashed_params[:guid])
    resource_not_found!(:service_usage_consumer) unless service_usage_consumer

    render status: :ok, json: Presenters::V3::ServiceUsageConsumerPresenter.new(service_usage_consumer)
  end

  def create
    unauthorized! unless permission_queryer.can_write_globally?

    message = ServiceUsageConsumerCreateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    service_usage_consumer = ServiceUsageConsumerCreate.create(message)

    render status: :created, json: Presenters::V3::ServiceUsageConsumerPresenter.new(service_usage_consumer)
  rescue ServiceUsageConsumerCreate::Error => e
    unprocessable!(e.message)
  end

  def update
    service_usage_consumer = ServiceUsageConsumer.find(guid: hashed_params[:guid])
    resource_not_found!(:service_usage_consumer) unless service_usage_consumer

    unauthorized! unless permission_queryer.can_write_globally?

    message = ServiceUsageConsumerUpdateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    service_usage_consumer = ServiceUsageConsumerUpdate.update(service_usage_consumer, message)

    render status: :ok, json: Presenters::V3::ServiceUsageConsumerPresenter.new(service_usage_consumer)
  rescue ServiceUsageConsumerUpdate::Error => e
    unprocessable!(e.message)
  end

  def destroy
    service_usage_consumer = ServiceUsageConsumer.find(guid: hashed_params[:guid])
    resource_not_found!(:service_usage_consumer) unless service_usage_consumer

    unauthorized! unless permission_queryer.can_write_globally?

    service_usage_consumer.db.transaction do
      service_usage_consumer.lock!

      service_usage_consumer.destroy
    end

    head :no_content
  end
end

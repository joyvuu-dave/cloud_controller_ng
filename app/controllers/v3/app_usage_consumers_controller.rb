require 'messages/app_usage_consumer_create_message'
require 'messages/app_usage_consumers_list_message'
require 'presenters/v3/app_usage_consumer_presenter'

class AppUsageConsumersController < ApplicationController
  def index
    dataset = AppUsageConsumer.all
    render status: :ok, json: { message: dataset }
  end

  def show
    app_usage_consumer = AppUsageConsumer.find(guid: hashed_params[:guid])
    resource_not_found!(:app_usage_consumer) unless app_usage_consumer

    render status: :ok, json: Presenters::V3::AppUsageConsumerPresenter.new(app_usage_consumer)
  end

  def create
    unauthorized! unless permission_queryer.can_write_globally?

    message = AppUsageConsumerCreateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    app_usage_consumer = AppUsageConsumerCreate.create(message)

    render status: :created, json: Presenters::V3::AppUsageConsumerPresenter.new(app_usage_consumer)
  rescue AppUsageConsumerCreate::Error => e
    unprocessable!(e.message)
  end

  def update
    app_usage_consumer = AppUsageConsumer.find(guid: hashed_params[:guid])
    resource_not_found!(:app_usage_consumer) unless app_usage_consumer

    unauthorized! unless permission_queryer.can_write_globally?

    message = AppUsageConsumerUpdateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    app_usage_consumer = AppUsageConsumerUpdate.update(app_usage_consumer, message)

    render status: :ok, json: Presenters::V3::AppUsageConsumerPresenter.new(app_usage_consumer)
  rescue AppUsageConsumerUpdate::Error => e
    unprocessable!(e.message)
  end

  def destroy
    app_usage_consumer = AppUsageConsumer.find(guid: hashed_params[:guid])
    resource_not_found!(:app_usage_consumer) unless app_usage_consumer

    unauthorized! unless permission_queryer.can_write_globally?

    app_usage_consumer.db.transaction do
      app_usage_consumer.lock!

      app_usage_consumer.destroy
    end

    head :no_content
  end
end

class AppUsageConsumersController < ApplicationController
  def destroy
    app_usage_consumer = AppUsageConsumer.find(consumer_guid: hashed_params[:guid])

    resource_not_found!(:app_usage_consumer) unless app_usage_consumer

    app_usage_consumer_access = VCAP::CloudController::AppUsageConsumerAccess.new(context: SecurityContext)
    unauthorized! unless app_usage_consumer_access.delete?(app_usage_consumer)

    app_usage_consumer.destroy

    head :no_content
  end
end

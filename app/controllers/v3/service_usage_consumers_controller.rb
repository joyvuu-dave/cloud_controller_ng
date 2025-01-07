class ServiceUsageConsumersController < ApplicationController
  def destroy
    service_usage_consumer = ServiceUsageConsumer.find(consumer_guid: hashed_params[:guid])

    resource_not_found!(:service_usage_consumer) unless service_usage_consumer

    service_usage_consumer_access = VCAP::CloudController::ServiceUsageConsumerAccess.new(context: SecurityContext)
    unauthorized! unless service_usage_consumer_access.delete?(service_usage_consumer)

    service_usage_consumer.destroy

    head :no_content
  end
end

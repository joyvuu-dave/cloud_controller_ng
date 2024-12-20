class ServiceUsageConsumersController < ApplicationController
  def destroy
    service_usage_consumer = ServiceUsageConsumer.find(consumer_guid: hashed_params[:guid])

    resource_not_found!(:service_usage_consumer) unless service_usage_consumer

    unless roles.admin?
      raise CloudController::Errors::ApiError.new_from_details('NotAuthorized')
    end

    service_usage_consumer.db.transaction do
      service_usage_consumer.lock!
      service_usage_consumer.destroy
    end

    head :no_content
  end
end

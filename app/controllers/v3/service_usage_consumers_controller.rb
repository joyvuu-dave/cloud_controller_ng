class ServiceUsageConsumersController < ApplicationController
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

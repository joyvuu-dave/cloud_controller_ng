class AppUsageConsumersController < ApplicationController
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

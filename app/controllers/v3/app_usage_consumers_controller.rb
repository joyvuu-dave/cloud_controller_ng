require 'controllers/base/base_controller'

class AppUsageConsumersController < VCAP::CloudController::RestController::BaseController
  def destroy
    check_authentication(:destroy)

    app_usage_consumer = AppUsageConsumer.find(consumer_guid: hashed_params[:guid])

    resource_not_found!(:app_usage_consumer) unless app_usage_consumer

    unless roles.admin?
      raise CloudController::Errors::ApiError.new_from_details('NotAuthorized')
    end

    app_usage_consumer.db.transaction do
      app_usage_consumer.lock!
      app_usage_consumer.destroy
    end

    head :no_content
  end
end

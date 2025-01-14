class AppUsageConsumersController < ApplicationController
  def index
    message = AppUsageConsumersListMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    dataset = AppUsageConsumerListFetcher.fetch_all(message)

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::AppUsageConsumerPresenter,
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      path: '/v3/app_usage_consumers',
      message: message
    )
  end

  def destroy
    app_usage_consumer = AppUsageConsumer.find(consumer_guid: hashed_params[:guid])

    resource_not_found!(:app_usage_consumer) unless app_usage_consumer

    app_usage_consumer_access = VCAP::CloudController::AppUsageConsumerAccess.new(context: SecurityContext)
    unauthorized! unless app_usage_consumer_access.delete?(app_usage_consumer)

    app_usage_consumer.destroy

    head :no_content
  end
end

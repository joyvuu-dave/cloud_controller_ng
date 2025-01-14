class ServiceUsageConsumersController < ApplicationController
  def index
    message = ServiceUsageConsumersListMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    dataset = ServiceUsageConsumerListFetcher.fetch_all(message)

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::ServiceUsageConsumerPresenter,
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      path: '/v3/service_usage_consumers',
      message: message
    )
  end

  def destroy
    service_usage_consumer = ServiceUsageConsumer.find(consumer_guid: hashed_params[:guid])

    resource_not_found!(:service_usage_consumer) unless service_usage_consumer

    service_usage_consumer_access = VCAP::CloudController::ServiceUsageConsumerAccess.new(context: SecurityContext)
    unauthorized! unless service_usage_consumer_access.delete?(service_usage_consumer)

    service_usage_consumer.destroy

    head :no_content
  end
end

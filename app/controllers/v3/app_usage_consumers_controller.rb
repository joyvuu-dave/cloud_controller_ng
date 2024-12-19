require 'messages/app_usage_consumer_create_message'
require 'messages/app_usage_consumers_list_message'
require 'presenters/v3/app_usage_consumer_presenter'
require 'actions/app_usage_consumer_create'

class AppUsageConsumersController < ApplicationController
  def index    
    #render status: :ok, json: { message: "Route hit successfully" }
    
    # message = "Great job hitting index!"
    #message = AppUsageConsumersListMessage.from_params(query_params)
    #invalid_param!(message.errors.full_messages) unless message.valid?

    # dataset = if permission_queryer.can_read_globally?
    #             #AppUsageConsumerListFetcher.fetch_all(message)
    #             "yo"
    #           else
    #             #AppUsageConsumerListFetcher.fetch_for_spaces(message, space_guids: permission_queryer.readable_space_guids)
    #             "dude"
    #           end
    dataset = AppUsageConsumer.all
    render status: :ok, json: { message: dataset }

    # render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
    #   presenter: Presenters::V3::AppUsageConsumerPresenter,
    #   paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
    #   path: '/v3/app_usage_consumers',
    #   message: message
    # )
  end

  def show
    app_usage_consumer = AppUsageConsumer.find(guid: hashed_params[:guid])
    resource_not_found!(:app_usage_consumer) unless app_usage_consumer

    render status: :ok, json: Presenters::V3::AppUsageConsumerPresenter.new(app_usage_consumer)
  end

  def create
    # logger.info("Auth token: #{VCAP::CloudController::SecurityContext.token}")
    # logger.info("Current user: #{VCAP::CloudController::SecurityContext.current_user}")
    # logger.info("Can write globally?: #{permission_queryer.can_write_globally?}")
    
    # render status: :ok, json: { 
    #   message: "Authentication checked",
    #   auth_info: {
    #     token_present: !VCAP::CloudController::SecurityContext.token.nil?,
    #     user_present: !VCAP::CloudController::SecurityContext.current_user.nil?,
    #     can_write: permission_queryer.can_write_globally?
    #   }
    # }

    # works
    # logger.info("Auth token: #{VCAP::CloudController::SecurityContext.token}")
    # logger.info("Current user: #{VCAP::CloudController::SecurityContext.current_user}")
    # render status: :ok, json: { message: "Authentication checked" }
    

    # logger.info("Request params: #{hashed_params.inspect}")
    # message = AppUsageConsumerCreateMessage.new(hashed_params[:body])
    # render status: :ok, json: { message: "Params received", data: message.to_param_hash }

    #render status: :ok, json: { message: "Route hit successfully" }

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

    AppUsageConsumerDelete.delete(app_usage_consumer)

    head :no_content
  end
end

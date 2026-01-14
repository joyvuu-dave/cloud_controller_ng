require 'presenters/v3/service_usage_snapshot_presenter'
require 'presenters/v3/service_usage_snapshot_detail_presenter'
require 'messages/service_usage_snapshots_create_message'
require 'messages/service_usage_snapshots_list_message'
require 'messages/service_usage_snapshot_details_list_message'
require 'fetchers/service_usage_snapshot_list_fetcher'
require 'fetchers/service_usage_snapshot_details_list_fetcher'
require 'jobs/runtime/service_usage_snapshot_generator_job'

class ServiceUsageSnapshotsController < ApplicationController
  def index
    message = ServiceUsageSnapshotsListMessage.from_params(query_params)
    unprocessable!(message.errors.full_messages) unless message.valid?

    unauthorized! unless permission_queryer.can_read_globally?

    dataset = ServiceUsageSnapshotListFetcher.fetch_all(message, ServiceUsageSnapshot.dataset)

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::ServiceUsageSnapshotPresenter,
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      path: '/v3/service_usage/snapshots',
      message: message
    )
  end

  def show
    unauthorized! unless permission_queryer.can_read_globally?

    snapshot = ServiceUsageSnapshot.first(guid: hashed_params[:guid])
    snapshot_not_found! unless snapshot

    render status: :ok, json: Presenters::V3::ServiceUsageSnapshotPresenter.new(snapshot)
  end

  def details
    message = ServiceUsageSnapshotDetailsListMessage.from_params(query_params)
    unprocessable!(message.errors.full_messages) unless message.valid?

    unauthorized! unless permission_queryer.can_read_globally?

    snapshot = ServiceUsageSnapshot.first(guid: hashed_params[:guid])
    snapshot_not_found! unless snapshot

    dataset = ServiceUsageSnapshotDetailsListFetcher.fetch_all(
      message,
      snapshot.service_usage_snapshot_details_dataset
    )

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::ServiceUsageSnapshotDetailPresenter,
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      path: "/v3/service_usage/snapshots/#{snapshot.guid}/details",
      message: message
    )
  end

  def create
    message = ServiceUsageSnapshotsCreateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    unauthorized! unless permission_queryer.can_write_globally?

    # Check for existing in-progress snapshot
    existing_snapshot = ServiceUsageSnapshot.where(completed_at: nil).first
    raise CloudController::Errors::ApiError.new_from_details('ServiceUsageSnapshotGenerationInProgress') if existing_snapshot

    job = Jobs::Runtime::ServiceUsageSnapshotGeneratorJob.new
    pollable_job = Jobs::Enqueuer.new(queue: Jobs::Queues.generic).enqueue_pollable(job)

    head :accepted, 'Location' => url_builder.build_url(path: "/v3/jobs/#{pollable_job.guid}")
  end

  private

  def snapshot_not_found!
    resource_not_found!(:service_usage_snapshot)
  end
end

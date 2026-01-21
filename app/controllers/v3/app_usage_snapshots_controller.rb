require 'presenters/v3/app_usage_snapshot_presenter'
require 'presenters/v3/app_usage_snapshot_space_presenter'
require 'messages/app_usage_snapshots_create_message'
require 'messages/app_usage_snapshots_list_message'
require 'fetchers/app_usage_snapshot_list_fetcher'
require 'jobs/runtime/app_usage_snapshot_generator_job'

class AppUsageSnapshotsController < ApplicationController
  def index
    message = AppUsageSnapshotsListMessage.from_params(query_params)
    unprocessable!(message.errors.full_messages) unless message.valid?

    # Return empty dataset for non-admin users (following ServiceUsageEventsController pattern)
    dataset = AppUsageSnapshot.where(guid: [])
    dataset = AppUsageSnapshotListFetcher.fetch_all(message, AppUsageSnapshot.dataset) if permission_queryer.can_read_globally?

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::AppUsageSnapshotPresenter,
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      path: '/v3/app_usage/snapshots',
      message: message
    )
  end

  def show
    # Return 404 for non-admin users (following ServiceUsageEventsController pattern)
    snapshot_not_found! unless permission_queryer.can_read_globally?

    snapshot = AppUsageSnapshot.first(guid: hashed_params[:guid])
    snapshot_not_found! unless snapshot

    render status: :ok, json: Presenters::V3::AppUsageSnapshotPresenter.new(snapshot)
  end

  def create
    message = AppUsageSnapshotsCreateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    unauthorized! unless permission_queryer.can_write_globally?

    # Check for existing in-progress snapshot (completed_at is NULL)
    existing_snapshot = AppUsageSnapshot.where(completed_at: nil).first
    raise CloudController::Errors::ApiError.new_from_details('AppUsageSnapshotGenerationInProgress') if existing_snapshot

    # Following the pattern established by CreateBindingAsyncJob:
    # Create the resource record FIRST, then pass its guid to the job.
    # This ensures PollableJobModel.resource_guid is set correctly at enqueue time.
    # See: app/jobs/v3/create_binding_async_job.rb lines 14-17
    #
    # We create a placeholder snapshot with minimal data. The job will populate
    # the actual checkpoint and counts. The snapshot is identifiable as "in progress"
    # by having completed_at = NULL.
    snapshot = AppUsageSnapshot.create(
      guid: SecureRandom.uuid,
      checkpoint_event_id: nil,
      created_at: Time.now.utc,
      completed_at: nil,
      instance_count: 0,
      organization_count: 0,
      space_count: 0
    )

    begin
      job = Jobs::Runtime::AppUsageSnapshotGeneratorJob.new(snapshot.guid)
      pollable_job = Jobs::Enqueuer.new(queue: Jobs::Queues.generic).enqueue_pollable(job)
    rescue StandardError
      # If job enqueue fails, delete the orphaned snapshot to avoid blocking future requests
      snapshot.destroy
      raise
    end

    head :accepted, 'Location' => url_builder.build_url(path: "/v3/jobs/#{pollable_job.guid}")
  end

  def spaces
    # Return 404 for non-admin users
    snapshot_not_found! unless permission_queryer.can_read_globally?

    snapshot = AppUsageSnapshot.first(guid: hashed_params[:guid])
    snapshot_not_found! unless snapshot

    # Only show spaces for completed snapshots
    unprocessable!('Snapshot is still processing') unless snapshot.complete?

    pagination_options = PaginationOptions.from_params(query_params)
    paginated_result = SequelPaginator.new.get_page(
      snapshot.app_usage_snapshot_spaces_dataset,
      pagination_options
    )

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::AppUsageSnapshotSpacePresenter,
      paginated_result: paginated_result,
      path: "/v3/app_usage/snapshots/#{snapshot.guid}/spaces"
    )
  end

  private

  def snapshot_not_found!
    resource_not_found!(:app_usage_snapshot)
  end
end

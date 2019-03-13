require 'messages/buildpack_create_message'
require 'messages/buildpacks_list_message'
require 'messages/buildpack_update_message'
require 'messages/buildpack_upload_message'
require 'fetchers/buildpack_list_fetcher'
require 'actions/buildpack_create'
require 'actions/buildpack_delete'
require 'actions/buildpack_update'
require 'actions/buildpack_upload'
require 'presenters/v3/buildpack_presenter'

class BuildpacksController < ApplicationController
  def index
    message = BuildpacksListMessage.from_params(query_params)
    invalid_param!(message.errors.full_messages) unless message.valid?

    dataset = BuildpackListFetcher.new.fetch_all(message)

    render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
      presenter: Presenters::V3::BuildpackPresenter(permission_queryer.can_write_globally?),
      paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
      path: '/v3/buildpacks',
      message: message
    )
  end

  def show
    buildpack = Buildpack.find(guid: hashed_params[:guid])
    buildpack_not_found! unless buildpack

    render status: :ok, json: Presenters::V3::BuildpackPresenter.new(permission_queryer.can_write_globally?, buildpack)
  end

  def create
    unauthorized! unless permission_queryer.can_write_globally?

    message = BuildpackCreateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    buildpack = BuildpackCreate.new.create(message)

    render status: :created, json: Presenters::V3::BuildpackPresenter.new(permission_queryer.can_write_globally?, buildpack)
  rescue BuildpackCreate::Error => e
    unprocessable!(e)
  end

  def destroy
    buildpack = Buildpack.find(guid: hashed_params[:guid])
    buildpack_not_found! unless buildpack

    unauthorized! unless permission_queryer.can_write_globally?

    delete_action = BuildpackDelete.new
    deletion_job = VCAP::CloudController::Jobs::DeleteActionJob.new(Buildpack, buildpack.guid, delete_action)
    pollable_job = Jobs::Enqueuer.new(deletion_job, queue: 'cc-generic').enqueue_pollable

    url_builder = VCAP::CloudController::Presenters::ApiUrlBuilder.new
    head :accepted, 'Location' => url_builder.build_url(path: "/v3/jobs/#{pollable_job.guid}")
  end

  def update
    buildpack = Buildpack.find(guid: hashed_params[:guid])
    buildpack_not_found! unless buildpack

    unauthorized! unless permission_queryer.can_write_globally?

    message = BuildpackUpdateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    buildpack = VCAP::CloudController::BuildpackUpdate.new.update(buildpack, message)

    render status: :ok, json: Presenters::V3::BuildpackPresenter.new(permission_queryer.can_write_globally?, buildpack)
  rescue BuildpackUpdate::Error => e
    unprocessable!(e)
  end

  def upload
    buildpack = Buildpack.find(guid: hashed_params[:guid])
    buildpack_not_found! unless buildpack

    unauthorized! unless permission_queryer.can_write_globally?

    message = BuildpackUploadMessage.create_from_params(hashed_params[:body])
    combine_messages(message.errors.full_messages) unless message.valid?

    unprocessable!('Buildpack is locked') if buildpack.locked

    pollable_job = BuildpackUpload.new.upload_async(
      message: message,
      buildpack: buildpack,
      config: configuration
    )

    url_builder = VCAP::CloudController::Presenters::ApiUrlBuilder.new
    response.set_header('Location', url_builder.build_url(path: "/v3/jobs/#{pollable_job.guid}"))
    render status: :accepted, json: Presenters::V3::BuildpackPresenter.new(permission_queryer.can_write_globally?, buildpack)
  rescue VCAP::CloudController::BuildpackUploadMessage::MissingFilePathError => e
    unprocessable!(e.message)
  end

  # TODO EARLY RETURN IF BITS SERVICE IS NOT ENABLED
  def associate_bits
    buildpack = Buildpack.find(guid: hashed_params[:guid])
    buildpack_not_found! unless buildpack

    unauthorized! unless permission_queryer.can_write_globally?

    # TODO CREATE MESSAGE

    # TODO MOVE TO ACTION
    buildpack_blobstore = CloudController::DependencyLocator.instance.buildpack_blobstore

    metadata = buildpack_blobstore.get_buildpack_metadata(params['bits_guid'])

    begin
      Buildpack.db.transaction do
        Locking[name: 'buildpacks'].lock!
        buildpack.update(
          key: metadata[:key],
          filename: metadata[:filename],
          sha256_checksum: metadata[:sha256],
          stack: metadata[:stack]
        )
      end
    rescue Sequel::ValidationFailed
      raise_translated_api_error(buildpack)
    end
    # TODO call to bits to persist the buildpack
    render status: :ok, json: Presenters::V3::BuildpackPresenter.new(permission_queryer.can_write_globally?, buildpack)
  end

  private

  def buildpack_not_found!
    resource_not_found!(:buildpack)
  end

  def combine_messages(messages)
    unprocessable!("Uploaded buildpack file is invalid: #{messages.join(', ')}")
  end

  def raise_translated_api_error(buildpack)
    if buildpack.errors.on([:name, :stack]).try(:include?, :unique)
      raise CloudController::Errors::ApiError.new_from_details('BuildpackNameStackTaken', buildpack.name, buildpack.stack)
    end
    if buildpack.errors.on(:stack).try(:include?, :buildpack_cant_change_stacks)
      raise CloudController::Errors::ApiError.new_from_details('BuildpackStacksDontMatch', buildpack.stack, buildpack.initial_value(:stack))
    end
    if buildpack.errors.on(:stack).try(:include?, :buildpack_stack_does_not_exist)
      raise CloudController::Errors::ApiError.new_from_details('BuildpackStackDoesNotExist', buildpack.stack)
    end
  end
end

require 'messages/internal_build_update_message'

# TODO: do make this an internal endpoint?
class Internal::BuildsController < ApplicationController

  # TODO: add authentication?

  def update
    build = BuildModel.find(guid: params[:guid])
    resource_not_found!(:build) unless build

    message = VCAP::CloudController::InternalBuildUpdateMessage.new(hashed_params[:body])
    unprocessable!(message.errors.full_messages) unless message.valid?

    # TODO: is this the best way to handle errors?
    if message.state == VCAP::CloudController::BuildModel::FAILED_STATE
      build.fail_to_stage!("StagerError", message.error)
    else
      #build = BuildUpdate.new.update(build, message)
      build.mark_as_staged
      build.save_changes
    end

    render status: :ok, json: Presenters::V3::BuildPresenter.new(build)
  end

  private

  # TODO: Remove these and figure out internal component auth
  def enforce_authentication?
    false
  end

  def enforce_write_scope?
    false
  end

end

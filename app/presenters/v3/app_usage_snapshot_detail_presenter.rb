require 'presenters/v3/base_presenter'

module VCAP::CloudController
  module Presenters
    module V3
      class AppUsageSnapshotDetailPresenter < BasePresenter
        def to_hash
          {
            organization_guid: detail.organization_guid,
            space_guid: detail.space_guid,
            app_guid: detail.app_guid,
            process_guid: detail.process_guid,
            process_type: detail.process_type,
            instances: detail.instances
          }
        end

        private

        def detail
          @resource
        end
      end
    end
  end
end

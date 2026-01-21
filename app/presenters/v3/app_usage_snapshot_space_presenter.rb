require 'presenters/v3/base_presenter'

module VCAP::CloudController
  module Presenters
    module V3
      class AppUsageSnapshotSpacePresenter < BasePresenter
        def to_hash
          {
            space_guid: space.space_guid,
            organization_guid: space.organization_guid,
            instance_count: space.instance_count,
            processes: space.processes || []
          }
        end

        private

        def space
          @resource
        end
      end
    end
  end
end

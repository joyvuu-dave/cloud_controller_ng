require 'presenters/v3/base_presenter'

module VCAP::CloudController
  module Presenters
    module V3
      class ServiceUsageSnapshotSpacePresenter < BasePresenter
        def to_hash
          {
            space_guid: space.space_guid,
            organization_guid: space.organization_guid,
            service_instance_count: space.service_instance_count,
            service_instances: space.service_instances || []
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

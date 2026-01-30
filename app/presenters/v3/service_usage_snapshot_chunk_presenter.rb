require 'presenters/v3/base_presenter'

module VCAP::CloudController
  module Presenters
    module V3
      class ServiceUsageSnapshotChunkPresenter < BasePresenter
        def to_hash
          {
            organization_guid: chunk.organization_guid,
            space_guid: chunk.space_guid,
            chunk_index: chunk.chunk_index,
            service_instance_count: chunk.service_instance_count,
            service_instances: chunk.service_instances || []
          }
        end

        private

        def chunk
          @resource
        end
      end
    end
  end
end

require 'presenters/v3/base_presenter'

module VCAP::CloudController
  module Presenters
    module V3
      class AppUsageSnapshotChunkPresenter < BasePresenter
        def to_hash
          {
            organization_guid: chunk.organization_guid,
            space_guid: chunk.space_guid,
            chunk_index: chunk.chunk_index,
            process_count: chunk.process_count,
            instance_count: chunk.instance_count,
            processes: chunk.processes || []
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

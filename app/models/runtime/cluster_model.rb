require 'cloud_controller/opi/base_client'

module VCAP::CloudController
  class ClusterModel < Sequel::Model(:clusters)
    many_to_one :space,
      class: 'VCAP::CloudController::Space',
      primary_key: :guid,
      key: :space_guid,
      without_guid_generation: true

    one_to_many :placement_splits,
      class: 'VCAP::CloudController::PlacementSplitModel',
      primary_key: :guid,
      key: :cluster_guid,
      without_guid_generation: true

  end
end

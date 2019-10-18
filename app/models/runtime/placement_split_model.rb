module VCAP::CloudController
  class PlacementSplitModel < Sequel::Model(:placement_splits)
    many_to_one :cluster,
      class: 'VCAP::CloudController::ClusterModel',
      primary_key: :guid,
      key: :cluster_guid,
      without_guid_generation: true

    many_to_one :placement,
      class: 'VCAP::CloudController::PlacementModel',
      primary_key: :guid,
      key: :placement_guid,
      without_guid_generation: true
  end
end

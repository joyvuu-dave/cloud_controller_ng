module VCAP::CloudController
  class PlacementBindingModel < Sequel::Model(:placement_bindings)
    many_to_one :placement,
      class: 'VCAP::CloudController::ClusterModel',
      primary_key: :guid,
      key: :placement_guid,
      without_guid_generation: true

    many_to_one :process,
      class: 'VCAP::CloudController::ProcessModel',
      primary_key: :guid,
      key: :process_guid,
      without_guid_generation: true
  end
end

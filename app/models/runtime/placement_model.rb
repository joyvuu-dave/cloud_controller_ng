module VCAP::CloudController
  class PlacementModel < Sequel::Model(:placements)
    many_to_one :space,
      class: 'VCAP::CloudController::Space',
      primary_key: :guid,
      key: :space_guid,
      without_guid_generation: true

    one_to_many :placement_splits,
      class: 'VCAP::CloudController::PlacementSplits',
      primary_key: :guid,
      key: :placement_guid,
      without_guid_generation: true

    def total_weight
      placement_splits.inject(0, { |sum, split|
        sum + split.weight
      })
    end
  end
end

require 'messages/list_message'

module VCAP::CloudController
  class AppUsageSnapshotDetailsListMessage < ListMessage
    register_allowed_keys %i[
      organization_guids
      space_guids
    ]

    validates_with NoAdditionalParamsValidator

    validates :organization_guids, array: true, allow_nil: true
    validates :space_guids, array: true, allow_nil: true

    def self.from_params(params)
      super(params, %w[organization_guids space_guids])
    end
  end
end

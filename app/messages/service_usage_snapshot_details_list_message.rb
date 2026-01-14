require 'messages/list_message'

module VCAP::CloudController
  class ServiceUsageSnapshotDetailsListMessage < ListMessage
    register_allowed_keys %i[
      organization_guids
      space_guids
      service_instance_guids
      service_plan_guids
      service_offering_guids
      service_broker_guids
    ]

    validates_with NoAdditionalParamsValidator

    validates :organization_guids, array: true, allow_nil: true
    validates :space_guids, array: true, allow_nil: true
    validates :service_instance_guids, array: true, allow_nil: true
    validates :service_plan_guids, array: true, allow_nil: true
    validates :service_offering_guids, array: true, allow_nil: true
    validates :service_broker_guids, array: true, allow_nil: true

    def self.from_params(params)
      super(params, %w[organization_guids space_guids service_instance_guids service_plan_guids service_offering_guids service_broker_guids])
    end
  end
end

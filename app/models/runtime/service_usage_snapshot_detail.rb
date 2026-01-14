module VCAP::CloudController
  class ServiceUsageSnapshotDetail < Sequel::Model(:service_usage_snapshot_details)
    many_to_one :service_usage_snapshot,
                class: 'VCAP::CloudController::ServiceUsageSnapshot',
                key: :snapshot_id,
                primary_key: :id

    def validate
      super
      validates_presence :snapshot_id
      validates_presence :organization_guid
      validates_presence :space_guid
      validates_presence :service_instance_guid
      validates_presence :service_instance_name
      validates_presence :service_instance_type
    end
  end
end

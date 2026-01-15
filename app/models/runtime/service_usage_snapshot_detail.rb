module VCAP::CloudController
  class ServiceUsageSnapshotDetail < Sequel::Model(:service_usage_snapshot_details)
    many_to_one :service_usage_snapshot,
                class: 'VCAP::CloudController::ServiceUsageSnapshot',
                key: :snapshot_id,
                primary_key: :id

    def validate
      super
      validates_presence :snapshot_id
      # NOTE: organization_guid and space_guid can be NULL when the org/space
      # has been deleted but the service instance still exists. The repository uses
      # LEFT JOIN specifically to handle this case. We intentionally do NOT
      # validate presence for these fields.
      validates_presence :service_instance_guid
      validates_presence :service_instance_name
      validates_presence :service_instance_type
    end
  end
end

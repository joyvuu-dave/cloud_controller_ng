module VCAP::CloudController
  class ServiceUsageSnapshotSpace < Sequel::Model(:service_usage_snapshot_spaces)
    plugin :serialization

    many_to_one :service_usage_snapshot

    serialize_attributes :json, :service_instances

    def validate
      super
      validates_presence :service_usage_snapshot_id
      validates_presence :space_guid
      validates_presence :organization_guid
      validates_presence :service_instance_count
    end
  end
end

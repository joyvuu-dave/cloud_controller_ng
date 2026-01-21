module VCAP::CloudController
  class AppUsageSnapshotSpace < Sequel::Model(:app_usage_snapshot_spaces)
    plugin :serialization

    many_to_one :app_usage_snapshot

    serialize_attributes :json, :processes

    def validate
      super
      validates_presence :app_usage_snapshot_id
      validates_presence :space_guid
      validates_presence :organization_guid
      validates_presence :instance_count
    end
  end
end

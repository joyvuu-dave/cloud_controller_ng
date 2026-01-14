module VCAP::CloudController
  class AppUsageSnapshotDetail < Sequel::Model(:app_usage_snapshot_details)
    many_to_one :usage_snapshot,
                class: 'VCAP::CloudController::AppUsageSnapshot',
                key: :snapshot_id,
                primary_key: :id

    def validate
      super
      validates_presence :snapshot_id
      validates_presence :organization_guid
      validates_presence :space_guid
      validates_presence :app_guid
      validates_presence :process_guid
      validates_presence :process_type
      validates_presence :instances
    end
  end
end

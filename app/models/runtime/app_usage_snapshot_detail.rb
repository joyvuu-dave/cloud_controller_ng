module VCAP::CloudController
  class AppUsageSnapshotDetail < Sequel::Model(:app_usage_snapshot_details)
    many_to_one :app_usage_snapshot,
                class: 'VCAP::CloudController::AppUsageSnapshot',
                key: :snapshot_id,
                primary_key: :id

    def validate
      super
      validates_presence :snapshot_id
      # NOTE: organization_guid and space_guid can be NULL when the org/space
      # has been deleted but the process is still running. The repository uses
      # LEFT JOIN specifically to handle this case. We intentionally do NOT
      # validate presence for these fields.
      validates_presence :app_guid
      validates_presence :process_guid
      validates_presence :process_type
      validates_presence :instances
    end
  end
end

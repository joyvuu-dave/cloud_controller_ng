module VCAP::CloudController
  class AppUsageSnapshot < Sequel::Model(:app_usage_snapshots)
    one_to_many :app_usage_snapshot_details,
                class: 'VCAP::CloudController::AppUsageSnapshotDetail',
                key: :snapshot_id,
                primary_key: :id

    # NOTE: The FK constraint on app_usage_snapshot_details has ON DELETE CASCADE,
    # which handles bulk deletes (used by cleanup job's .delete method).
    # The add_association_dependencies handles individual .destroy calls.
    add_association_dependencies app_usage_snapshot_details: :destroy

    def validate
      super
      validates_presence :guid
      # NOTE: checkpoint_event_id and checkpoint_event_created_at can be NULL when
      # the snapshot is first created (placeholder) or when there are no usage events
      # (empty system). The columns are intentionally nullable in the migration.
      validates_presence :created_at
      validates_presence :process_count
      validates_presence :organization_count
      validates_presence :space_count
    end

    def before_create
      super
      self.guid ||= SecureRandom.uuid
    end

    def processing?
      completed_at.nil?
    end

    def complete?
      !completed_at.nil?
    end
  end
end

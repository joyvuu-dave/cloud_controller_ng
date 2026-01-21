module VCAP::CloudController
  class AppUsageSnapshot < Sequel::Model(:app_usage_snapshots)
    plugin :after_initialize

    one_to_many :app_usage_snapshot_spaces

    def validate
      super
      validates_presence :guid
      # NOTE: checkpoint_event_id and checkpoint_event_created_at can be NULL when
      # the snapshot is first created (placeholder) or when there are no usage events
      # (empty system). The columns are intentionally nullable in the migration.
      validates_presence :created_at
      validates_presence :instance_count
      validates_presence :organization_count
      validates_presence :space_count
    end

    def after_initialize
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

module VCAP::CloudController
  class ServiceUsageSnapshot < Sequel::Model(:service_usage_snapshots)
    one_to_many :service_usage_snapshot_details,
                class: 'VCAP::CloudController::ServiceUsageSnapshotDetail',
                key: :snapshot_id,
                primary_key: :id

    add_association_dependencies service_usage_snapshot_details: :destroy

    def validate
      super
      validates_presence :guid
      validates_presence :checkpoint_event_id
      validates_presence :checkpoint_event_created_at
      validates_presence :created_at
      validates_presence :service_instance_count
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

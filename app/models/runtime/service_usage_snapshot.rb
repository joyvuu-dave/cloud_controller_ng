module VCAP::CloudController
  class ServiceUsageSnapshot < Sequel::Model(:service_usage_snapshots)
    one_to_many :service_usage_snapshot_details,
                class: 'VCAP::CloudController::ServiceUsageSnapshotDetail',
                key: :snapshot_id,
                primary_key: :id

    # NOTE: The FK constraint on service_usage_snapshot_details has ON DELETE CASCADE,
    # which handles bulk deletes (used by cleanup job's .delete method).
    # The add_association_dependencies handles individual .destroy calls.
    add_association_dependencies service_usage_snapshot_details: :destroy

    def validate
      super
      validates_presence :guid
      validates_presence :checkpoint_event_id
      # NOTE: checkpoint_event_created_at can be NULL when there are no usage events
      # (empty system). The column is intentionally nullable in the migration.
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

    # Verifies the integrity of a completed snapshot.
    #
    # This method checks two conditions:
    # 1. The snapshot has completed (completed_at is not NULL)
    # 2. The number of detail records matches the expected count
    #
    # WHY THIS IS NECESSARY:
    # During snapshot generation, we first count service instances via SQL, then batch-insert
    # detail records. If the database crashes, the transaction rolls back, or any other
    # failure occurs mid-generation, we could end up with:
    # - A snapshot stuck in "processing" state (completed_at is NULL)
    # - A snapshot marked complete but with fewer details than expected
    #
    # HOW IT WORKS:
    # - service_instance_count is set from SQL COUNT(*) BEFORE inserting details
    # - Details are inserted in batches within the same transaction
    # - completed_at is set AFTER all details are inserted
    # - If anything fails, the transaction rolls back entirely
    #
    # WHAT IT CATCHES:
    # - Partial failures where some batches inserted but not all
    # - Snapshots stuck in processing state
    # - Any mismatch between expected and actual detail count
    #
    # WHAT IT DOESN'T CATCH:
    # - Logical errors in the query (wrong service instances selected)
    # - Data corruption within individual records
    #
    # USAGE:
    # Billing consumers should call this before trusting snapshot data:
    #   if snapshot.integrity_valid?
    #     process_for_billing(snapshot)
    #   else
    #     request_new_snapshot
    #   end
    #
    # @return [Boolean] true if snapshot is complete and has correct detail count
    def integrity_valid?
      complete? && service_instance_count == service_usage_snapshot_details.count
    end
  end
end

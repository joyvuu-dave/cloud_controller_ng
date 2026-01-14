Sequel.migration do
  up do
    create_table :service_usage_snapshots do
      primary_key :id, type: :Bignum, name: :service_usage_snapshots_pk
      String :guid, null: false, size: 255
      column :checkpoint_event_id, :Bignum, null: false
      Timestamp :checkpoint_event_created_at, null: true
      Timestamp :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      Timestamp :completed_at, null: true
      Integer :service_instance_count, null: false, default: 0
      Integer :organization_count, null: false, default: 0
      Integer :space_count, null: false, default: 0

      index :guid, unique: true, name: :service_usage_snapshots_guid_index
      index :created_at, name: :service_usage_snapshots_created_at_index
      index :completed_at, name: :service_usage_snapshots_completed_at_index
      index :checkpoint_event_id, name: :service_usage_snapshots_checkpoint_event_id_index
    end

    create_table :service_usage_snapshot_details do
      primary_key :id, type: :Bignum, name: :service_usage_snapshot_details_pk
      column :snapshot_id, :Bignum, null: false
      String :organization_guid, null: false, size: 255
      String :space_guid, null: false, size: 255
      String :service_instance_guid, null: false, size: 255
      String :service_instance_name, null: false, size: 255
      String :service_instance_type, null: false, size: 255
      String :service_plan_guid, null: true, size: 255
      String :service_plan_name, null: true, size: 255
      String :service_offering_guid, null: true, size: 255
      String :service_offering_name, null: true, size: 255
      String :service_broker_guid, null: true, size: 255
      String :service_broker_name, null: true, size: 255

      foreign_key [:snapshot_id], :service_usage_snapshots, name: :fk_service_usage_snapshot_details_snapshot_id, on_delete: :cascade
      index :snapshot_id, name: :service_usage_snapshot_details_snapshot_id_index
      index %i[snapshot_id organization_guid], name: :service_usage_snapshot_details_snapshot_id_org_guid_index
      index %i[snapshot_id space_guid], name: :service_usage_snapshot_details_snapshot_id_space_guid_index
      index %i[snapshot_id service_instance_guid], name: :service_usage_snapshot_details_snapshot_id_si_guid_index
    end
  end

  down do
    drop_table :service_usage_snapshot_details
    drop_table :service_usage_snapshots
  end
end

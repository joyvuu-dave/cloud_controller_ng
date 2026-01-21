Sequel.migration do
  up do
    create_table :service_usage_snapshots do
      primary_key :id, type: :Bignum, name: :id
      String :guid, null: false, size: 255
      column :checkpoint_event_id, :Bignum, null: true
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

    create_table :service_usage_snapshot_spaces do
      primary_key :id, type: :Bignum, name: :id
      column :service_usage_snapshot_id, :Bignum, null: false
      String :space_guid, null: false, size: 255
      String :organization_guid, null: false, size: 255
      Integer :service_instance_count, null: false, default: 0
      Text :service_instances, null: true

      foreign_key [:service_usage_snapshot_id], :service_usage_snapshots, name: :fk_svc_usage_snapshot_space_snapshot_id, on_delete: :cascade
      index :service_usage_snapshot_id, name: :service_usage_snapshot_spaces_snapshot_id_index
      index :space_guid, name: :service_usage_snapshot_spaces_space_guid_index
    end
  end

  down do
    drop_table :service_usage_snapshot_spaces
    drop_table :service_usage_snapshots
  end
end

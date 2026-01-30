Sequel.migration do
  up do
    create_table :app_usage_snapshots do
      primary_key :id, type: :Bignum, name: :id
      String :guid, null: false, size: 255
      column :checkpoint_event_id, :Bignum, null: true
      Timestamp :checkpoint_event_created_at, null: true
      Timestamp :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      Timestamp :completed_at, null: true
      Integer :instance_count, null: false, default: 0
      Integer :organization_count, null: false, default: 0
      Integer :space_count, null: false, default: 0

      index :guid, unique: true, name: :app_usage_snapshots_guid_index
      index :created_at, name: :app_usage_snapshots_created_at_index
      index :completed_at, name: :app_usage_snapshots_completed_at_index
      index :checkpoint_event_id, name: :app_usage_snapshots_checkpoint_event_id_index
    end

    create_table :app_usage_snapshot_spaces do
      primary_key :id, type: :Bignum, name: :id
      column :app_usage_snapshot_id, :Bignum, null: false
      String :space_guid, null: false, size: 255
      String :organization_guid, null: false, size: 255
      Integer :instance_count, null: false, default: 0
      Text :processes, null: true

      foreign_key [:app_usage_snapshot_id], :app_usage_snapshots, name: :fk_app_usage_snapshot_space_snapshot_id, on_delete: :cascade
      index :app_usage_snapshot_id, name: :app_usage_snapshot_spaces_snapshot_id_index
      index :space_guid, name: :app_usage_snapshot_spaces_space_guid_index
    end
  end

  down do
    drop_table :app_usage_snapshot_spaces
    drop_table :app_usage_snapshots
  end
end

Sequel.migration do
  up do
    create_table :app_usage_snapshots do
      primary_key :id, type: :Bignum
      String :guid, null: false, size: 255
      column :checkpoint_event_id, :Bignum, null: true
      Timestamp :checkpoint_event_created_at, null: true
      Timestamp :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      Timestamp :completed_at, null: true
      Integer :process_count, null: false, default: 0
      Integer :organization_count, null: false, default: 0
      Integer :space_count, null: false, default: 0

      index :guid, unique: true, name: :app_usage_snapshots_guid_index
      index :created_at, name: :app_usage_snapshots_created_at_index
      index :completed_at, name: :app_usage_snapshots_completed_at_index
      index :checkpoint_event_id, name: :app_usage_snapshots_checkpoint_event_id_index
    end

    create_table :app_usage_snapshot_details do
      primary_key :id, type: :Bignum
      column :snapshot_id, :Bignum, null: false
      String :organization_guid, null: true, size: 255
      String :space_guid, null: true, size: 255
      String :app_guid, null: false, size: 255
      String :process_guid, null: false, size: 255
      String :process_type, null: false, size: 255
      Integer :instances, null: false

      foreign_key [:snapshot_id], :app_usage_snapshots, name: :fk_app_usage_snapshot_details_snapshot_id, on_delete: :cascade
      index :snapshot_id, name: :app_usage_snapshot_details_snapshot_id_index
      index %i[snapshot_id organization_guid], name: :app_usage_snapshot_details_snapshot_id_org_guid_index
      index %i[snapshot_id space_guid], name: :app_usage_snapshot_details_snapshot_id_space_guid_index
    end
  end

  down do
    drop_table :app_usage_snapshot_details
    drop_table :app_usage_snapshots
  end
end

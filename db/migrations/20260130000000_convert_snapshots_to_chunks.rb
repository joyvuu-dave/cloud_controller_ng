# Migration to convert app_usage_snapshot_spaces to app_usage_snapshot_chunks
#
# This migration implements simple fixed-size chunking for app usage snapshots.
# Each chunk contains up to 100 processes for a single space. If a space has
# more than 100 processes, it gets multiple chunks.
#
# Key changes:
# - Adds chunk_count and last_processed_process_id to app_usage_snapshots
#   (chunk_count tracks total chunks, last_processed_process_id enables resumability)
# - Creates app_usage_snapshot_chunks table replacing app_usage_snapshot_spaces
# - Adds index on processes(state, id) for efficient streaming queries
#
# The same changes are applied to service_usage_snapshots for consistency.

Sequel.migration do
  up do
    # Add chunking support to app_usage_snapshots
    alter_table :app_usage_snapshots do
      add_column :chunk_count, Integer, null: false, default: 0
      add_column :process_count, Integer, null: false, default: 0
      add_column :last_processed_process_id, :Bignum, null: true
    end

    # Add chunking support to service_usage_snapshots
    alter_table :service_usage_snapshots do
      add_column :chunk_count, Integer, null: false, default: 0
      add_column :service_instance_count, Integer, null: false, default: 0
      add_column :last_processed_service_instance_id, :Bignum, null: true
    end

    # Create chunks table for app usage snapshots
    create_table :app_usage_snapshot_chunks do
      primary_key :id, type: :Bignum
      column :app_usage_snapshot_id, :Bignum, null: false
      String :organization_guid, null: false, size: 255
      String :space_guid, null: false, size: 255
      Integer :chunk_index, null: false, default: 0
      Integer :process_count, null: false, default: 0
      Integer :instance_count, null: false, default: 0
      Text :processes, null: false

      index %i[app_usage_snapshot_id space_guid chunk_index],
            name: :app_snapshot_chunks_space_idx
      foreign_key [:app_usage_snapshot_id], :app_usage_snapshots,
                  name: :fk_app_snapshot_chunk_snapshot_id,
                  on_delete: :cascade
    end

    # Create chunks table for service usage snapshots
    create_table :service_usage_snapshot_chunks do
      primary_key :id, type: :Bignum
      column :service_usage_snapshot_id, :Bignum, null: false
      String :organization_guid, null: false, size: 255
      String :space_guid, null: false, size: 255
      Integer :chunk_index, null: false, default: 0
      Integer :service_instance_count, null: false, default: 0
      Text :service_instances, null: false

      index %i[service_usage_snapshot_id space_guid chunk_index],
            name: :svc_snapshot_chunks_space_idx
      foreign_key [:service_usage_snapshot_id], :service_usage_snapshots,
                  name: :fk_svc_snapshot_chunk_snapshot_id,
                  on_delete: :cascade
    end

    # Add composite index on processes for efficient streaming queries.
    # This index supports WHERE state = 'STARTED' ORDER BY id queries
    # used by paged_each in the chunk generator.
    add_index :processes, %i[state id], name: :processes_state_id_index, if_not_exists: true

    # Drop old space tables
    drop_table :app_usage_snapshot_spaces
    drop_table :service_usage_snapshot_spaces
  end

  down do
    # Recreate old space tables
    create_table :app_usage_snapshot_spaces do
      primary_key :id, type: :Bignum
      column :app_usage_snapshot_id, :Bignum, null: false
      String :space_guid, null: false, size: 255
      String :organization_guid, null: false, size: 255
      Integer :instance_count, null: false, default: 0
      Text :processes, null: true

      foreign_key [:app_usage_snapshot_id], :app_usage_snapshots,
                  name: :fk_app_usage_snapshot_space_snapshot_id,
                  on_delete: :cascade
      index :app_usage_snapshot_id, name: :app_usage_snapshot_spaces_snapshot_id_index
      index :space_guid, name: :app_usage_snapshot_spaces_space_guid_index
    end

    create_table :service_usage_snapshot_spaces do
      primary_key :id, type: :Bignum
      column :service_usage_snapshot_id, :Bignum, null: false
      String :space_guid, null: false, size: 255
      String :organization_guid, null: false, size: 255
      Integer :service_instance_count, null: false, default: 0
      Text :service_instances, null: true

      foreign_key [:service_usage_snapshot_id], :service_usage_snapshots,
                  name: :fk_service_usage_snapshot_space_snapshot_id,
                  on_delete: :cascade
      index :service_usage_snapshot_id, name: :service_usage_snapshot_spaces_snapshot_id_index
      index :space_guid, name: :service_usage_snapshot_spaces_space_guid_index
    end

    # Drop new chunks tables
    drop_table :app_usage_snapshot_chunks
    drop_table :service_usage_snapshot_chunks

    # Remove index
    drop_index :processes, name: :processes_state_id_index, if_exists: true

    # Remove columns from snapshots
    alter_table :app_usage_snapshots do
      drop_column :chunk_count
      drop_column :process_count
      drop_column :last_processed_process_id
    end

    alter_table :service_usage_snapshots do
      drop_column :chunk_count
      drop_column :service_instance_count
      drop_column :last_processed_service_instance_id
    end
  end
end

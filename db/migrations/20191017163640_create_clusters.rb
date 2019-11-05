Sequel.migration do
  change do
    create_table(:clusters) do
      VCAP::Migration.common(self)

      String :name, size: 50, null: false

      String :url, size: 255, null: false

      String :space_guid, size: 255, null: false

      String :ca_cert, null: false, default: ""
      String :client_cert, null: false, default: ""
      String :client_key, null: false, default: ""

      foreign_key [:space_guid], :spaces, key: :guid, name: :clusters_space_guid_fkey
    end

    create_table(:placements) do
      VCAP::Migration.common(self)

      String :space_guid, size: 255, null: false
      String :name, size: 50, null: false

      foreign_key [:space_guid], :spaces, key: :guid, name: :placements_space_guid_fkey
    end

    create_table(:placement_splits) do
      VCAP::Migration.common(self)

      String :placement_guid, size: 255, null: false
      String :cluster_guid, size: 255, null: false
      Integer :weight, default: 1

      foreign_key [:placement_guid], :placements, key: :guid, name: :placements_splits_placement_guid_fkey
      foreign_key [:cluster_guid], :clusters, key: :guid, name: :placements_cluster_guid_fkey
    end

    create_table(:placement_bindings) do
      VCAP::Migration.common(self)

      String :process_guid, size: 255, null: false
      String :placement_guid, size: 255, null: false

      foreign_key [:placement_guid], :placements, key: :guid, name: :placements_bindings_placement_guid_fkey
      foreign_key [:process_guid], :processes, key: :guid, name: :placements_bindings_processes_guid_fkey
    end

    alter_table(:processes) do
      add_column :placement_binding_guid, String, size: 255
    end
  end
end

Sequel.migration do
  change do
    create_table(:service_instance_usages) do
      VCAP::Migration.common(self)

      DateTime :instance_created_at, null: false
      DateTime :instance_deleted_at
      String :org_guid, size: 255
      String :space_guid, size: 255
      String :space_name, size: 255
      String :service_instance_name, size: 255
      String :service_instance_guid, size: 255
      String :service_instance_type, size: 255
      String :service_plan_guid, size: 255
      String :service_plan_name, size: 255
      String :service_guid, size: 255
      String :service_label, size: 255
    end
  end
end

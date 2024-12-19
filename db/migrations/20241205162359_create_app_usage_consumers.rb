Sequel.migration do
  change do
    create_table :app_usage_consumers do |_t|
      primary_key :id, name: :id
      String :consumer_guid, null: false, size: 255
      String :last_processed_guid, null: false, size: 255

      DateTime :created_at, null: false
      DateTime :updated_at, null: false
    end
  end
end

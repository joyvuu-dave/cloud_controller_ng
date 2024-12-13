Sequel.migration do
  change do
    create_table :usage_event_consumers do |_t|
      primary_key :id, name: :id
      String :consumer_guid, null: false, size: 255
      String :last_event_guid, null: false, size: 255
      String :model_name, null: false, size: 255

      DateTime :created_at, null: false
      DateTime :updated_at, null: false
    end
  end
end

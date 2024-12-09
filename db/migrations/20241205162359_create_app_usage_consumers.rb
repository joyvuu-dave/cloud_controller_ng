Sequel.migration do
  change do
    create_table :app_usage_consumers do |_t|
      primary_key :id, name: :id
      String :consumer_id, null: false, size: 255
      String :last_app_usage_event_id, null: fals, size: 255

      DateTime :created_at, null: false
      DateTime :updated_at, null: false
    end
  end
end

Sequel.migration do
  up do
    unless self[:app_usage_events].columns.include?(:expiration)
      alter_table :app_usage_events do 
        add_column :expiration, :timestamp
      end
  end

  down do 
    alter_table :app_usage_events do 
      drop_column :expiration
    end
  end
end

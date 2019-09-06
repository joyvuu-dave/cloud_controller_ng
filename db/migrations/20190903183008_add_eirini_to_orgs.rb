Sequel.migration do
  change do
    alter_table :organizations do
      add_column :eirini, :boolean, default: false, nullable: false
    end
  end
end

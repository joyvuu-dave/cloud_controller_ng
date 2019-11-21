Sequel.migration do
  change do
    alter_table :domains do
      add_column :global_default, :boolean, default: false
    end
  end
end

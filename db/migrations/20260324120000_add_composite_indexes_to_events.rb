# rubocop:disable Metrics/BlockLength
Sequel.migration do
  no_transaction # required for concurrently option on postgres

  up do
    if database_type == :postgres
      VCAP::Migration.with_concurrent_timeout(self) do
        add_index :events, %i[actee created_at guid],
                  name: :events_actee_created_at_guid_index,
                  if_not_exists: true,
                  concurrently: true

        add_index :events, %i[space_guid created_at guid],
                  name: :events_space_guid_created_at_guid_index,
                  if_not_exists: true,
                  concurrently: true

        add_index :events, %i[organization_guid created_at guid],
                  name: :events_organization_guid_created_at_guid_index,
                  if_not_exists: true,
                  concurrently: true
      end
    else
      alter_table(:events) do
        # rubocop:disable Sequel/ConcurrentIndex
        unless @db.indexes(:events).key?(:events_actee_created_at_guid_index)
          add_index %i[actee created_at guid],
                    name: :events_actee_created_at_guid_index
        end
        unless @db.indexes(:events).key?(:events_space_guid_created_at_guid_index)
          add_index %i[space_guid created_at guid],
                    name: :events_space_guid_created_at_guid_index
        end
        unless @db.indexes(:events).key?(:events_organization_guid_created_at_guid_index)
          add_index %i[organization_guid created_at guid],
                    name: :events_organization_guid_created_at_guid_index
        end
        # rubocop:enable Sequel/ConcurrentIndex
      end
    end
  end

  down do
    if database_type == :postgres
      VCAP::Migration.with_concurrent_timeout(self) do
        drop_index :events, nil,
                   name: :events_actee_created_at_guid_index,
                   if_exists: true,
                   concurrently: true

        drop_index :events, nil,
                   name: :events_space_guid_created_at_guid_index,
                   if_exists: true,
                   concurrently: true

        drop_index :events, nil,
                   name: :events_organization_guid_created_at_guid_index,
                   if_exists: true,
                   concurrently: true
      end
    else
      alter_table(:events) do
        # rubocop:disable Sequel/ConcurrentIndex
        drop_index nil, name: :events_actee_created_at_guid_index if @db.indexes(:events).key?(:events_actee_created_at_guid_index)
        drop_index nil, name: :events_space_guid_created_at_guid_index if @db.indexes(:events).key?(:events_space_guid_created_at_guid_index)
        drop_index nil, name: :events_organization_guid_created_at_guid_index if @db.indexes(:events).key?(:events_organization_guid_created_at_guid_index)
        # rubocop:enable Sequel/ConcurrentIndex
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength

Sequel.migration do
  no_transaction # adding an index concurrently cannot be done within a transaction

  up do
    # Index to support efficient lookup of jobs by resource.
    # Used by snapshot presenters to find the associated job when rendering
    # in-progress snapshots. Without this index, the query does a full table scan.
    #
    # Query pattern:
    #   PollableJobModel.where(resource_type: 'app_usage_snapshot', resource_guid: snapshot.guid).first
    if database_type == :postgres
      VCAP::Migration.with_concurrent_timeout(self) do
        add_index :jobs, %i[resource_type resource_guid],
                  name: :jobs_resource_type_guid_index,
                  if_not_exists: true,
                  concurrently: true
      end
    else
      # MySQL: non-concurrent index
      # rubocop:disable Sequel/ConcurrentIndex
      add_index :jobs, %i[resource_type resource_guid],
                name: :jobs_resource_type_guid_index,
                if_not_exists: true
      # rubocop:enable Sequel/ConcurrentIndex
    end
  end

  down do
    if database_type == :postgres
      VCAP::Migration.with_concurrent_timeout(self) do
        drop_index :jobs, %i[resource_type resource_guid], name: :jobs_resource_type_guid_index, if_exists: true, concurrently: true
      end
    else
      # rubocop:disable Sequel/ConcurrentIndex
      drop_index :jobs, %i[resource_type resource_guid], name: :jobs_resource_type_guid_index, if_exists: true
      # rubocop:enable Sequel/ConcurrentIndex
    end
  end
end

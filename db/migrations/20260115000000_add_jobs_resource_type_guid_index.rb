Sequel.migration do
  up do
    # Index to support efficient lookup of jobs by resource.
    # Used by snapshot presenters to find the associated job when rendering
    # in-progress snapshots. Without this index, the query does a full table scan.
    #
    # Query pattern:
    #   PollableJobModel.where(resource_type: 'app_usage_snapshot', resource_guid: snapshot.guid).first
    add_index :jobs, %i[resource_type resource_guid],
              name: :jobs_resource_type_guid_index,
              if_not_exists: true,
              concurrently: true
  end

  down do
    drop_index :jobs, name: :jobs_resource_type_guid_index, if_exists: true, concurrently: true
  end
end

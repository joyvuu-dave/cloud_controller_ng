Sequel.migration do
  up do
    uuid_fn = case database_type
              when :postgres then 'get_uuid()'
              when :mysql then 'UUID()'
              else raise "unsupported database: #{database_type}"
              end

    transaction do
      run <<~SQL.squish
        INSERT INTO app_usage_events (
          guid, created_at,
          state, previous_state,
          instance_count, previous_instance_count,
          memory_in_mb_per_instance, previous_memory_in_mb_per_instance,
          app_guid, app_name,
          parent_app_guid, parent_app_name,
          space_guid, space_name, org_guid,
          buildpack_guid, buildpack_name,
          package_state, previous_package_state
        )
        SELECT
          #{uuid_fn}, CURRENT_TIMESTAMP,
          'WAS_RUNNING', NULL,
          p.instances, p.instances,
          p.memory, p.memory,
          p.guid, parent_app.name,
          parent_app.guid, parent_app.name,
          spaces.guid, spaces.name, organizations.guid,
          desired_droplet.buildpack_receipt_buildpack_guid, desired_droplet.buildpack_receipt_buildpack,
          CASE
            WHEN latest_droplet.state = 'FAILED' THEN 'FAILED'
            WHEN latest_droplet.state = 'STAGED' AND latest_droplet.guid = parent_app.droplet_guid THEN 'STAGED'
            WHEN latest_package.state = 'FAILED' THEN 'FAILED'
            ELSE 'PENDING'
          END,
          'UNKNOWN'
        FROM processes p
        INNER JOIN apps parent_app ON parent_app.guid = p.app_guid
        INNER JOIN spaces ON spaces.guid = parent_app.space_guid
        INNER JOIN organizations ON organizations.id = spaces.organization_id
        LEFT JOIN droplets desired_droplet ON desired_droplet.guid = parent_app.droplet_guid
        LEFT JOIN (
          SELECT pkg.guid, pkg.app_guid, pkg.state
          FROM packages pkg
          INNER JOIN (
            SELECT app_guid, MAX(id) AS max_id FROM packages GROUP BY app_guid
          ) lp_ids ON lp_ids.app_guid = pkg.app_guid AND lp_ids.max_id = pkg.id
        ) latest_package ON latest_package.app_guid = parent_app.guid
        LEFT JOIN (
          SELECT d.guid, d.package_guid, d.state
          FROM droplets d
          INNER JOIN (
            SELECT package_guid, MAX(id) AS max_id FROM droplets GROUP BY package_guid
          ) ld_ids ON ld_ids.package_guid = d.package_guid AND ld_ids.max_id = d.id
        ) latest_droplet ON latest_droplet.package_guid = latest_package.guid
        WHERE p.state = 'STARTED'
        ORDER BY p.id
      SQL
    end
  end

  down do
    self[:app_usage_events].where(state: 'WAS_RUNNING').delete
  end
end

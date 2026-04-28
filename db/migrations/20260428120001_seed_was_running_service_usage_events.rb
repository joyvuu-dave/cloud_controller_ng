Sequel.migration do
  up do
    uuid_fn = case database_type
              when :postgres then 'get_uuid()'
              when :mysql then 'UUID()'
              else raise "unsupported database: #{database_type}"
              end

    transaction do
      run <<~SQL.squish
        INSERT INTO service_usage_events (
          guid, created_at, state,
          service_instance_guid, service_instance_name, service_instance_type,
          service_plan_guid, service_plan_name,
          service_guid, service_label,
          service_broker_name, service_broker_guid,
          space_guid, space_name, org_guid
        )
        SELECT
          #{uuid_fn}, CURRENT_TIMESTAMP, 'WAS_RUNNING',
          service_instances.guid, service_instances.name,
          CASE WHEN service_instances.is_gateway_service THEN 'managed_service_instance' ELSE 'user_provided_service_instance' END,
          service_plans.guid, service_plans.name,
          services.guid, services.label,
          service_brokers.name, service_brokers.guid,
          spaces.guid, spaces.name, organizations.guid
        FROM service_instances
        INNER JOIN spaces ON spaces.id = service_instances.space_id
        INNER JOIN organizations ON organizations.id = spaces.organization_id
        LEFT OUTER JOIN service_plans ON service_plans.id = service_instances.service_plan_id
        LEFT OUTER JOIN services ON services.id = service_plans.service_id
        LEFT OUTER JOIN service_brokers ON service_brokers.id = services.service_broker_id
        ORDER BY service_instances.id
      SQL
    end
  end

  down do
    self[:service_usage_events].where(state: 'WAS_RUNNING').delete
  end
end

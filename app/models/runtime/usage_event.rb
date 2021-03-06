module VCAP::CloudController
  class UsageEvent < Sequel::Model(
    AppUsageEvent.select(
      Sequel.as('app', :type),
      :app_guid,
      :app_name,
      :buildpack_guid,
      :buildpack_name,
      :created_at,
      :guid,
      :instance_count,
      :memory_in_mb_per_instance,
      :org_guid,
      :parent_app_guid,
      :parent_app_name,
      :previous_instance_count,
      :previous_memory_in_mb_per_instance,
      :previous_state,
      :process_type,
      Sequel.as(nil, :service_broker_guid),
      Sequel.as(nil, :service_broker_name),
      Sequel.as(nil, :service_guid),
      Sequel.as(nil, :service_instance_guid),
      Sequel.as(nil, :service_instance_name),
      Sequel.as(nil, :service_instance_type),
      Sequel.as(nil, :service_label),
      Sequel.as(nil, :service_plan_guid),
      Sequel.as(nil, :service_plan_name),
      :space_guid,
      :space_name,
      :state,
      :task_guid,
      :task_name,
      Sequel.as(:created_at, :updated_at)
    ).union(
      ServiceUsageEvent.select(
        Sequel.as('service', :type),
        Sequel.as(nil, :app_guid),
        Sequel.as(nil, :app_name),
        Sequel.as(nil, :buildpack_guid),
        Sequel.as(nil, :buildpack_name),
        :created_at,
        :guid,
        Sequel.as(nil, :instance_count),
        Sequel.as(nil, :memory_in_mb_per_instance),
        :org_guid,
        Sequel.as(nil, :parent_app_guid),
        Sequel.as(nil, :parent_app_name),
        Sequel.as(nil, :previous_instance_count),
        Sequel.as(nil, :previous_memory_in_mb_per_instance),
        Sequel.as(nil, :previous_state),
        Sequel.as(nil, :process_type),
        :service_broker_guid,
        :service_broker_name,
        :service_guid,
        :service_instance_guid,
        :service_instance_name,
        :service_instance_type,
        :service_label,
        :service_plan_guid,
        :service_plan_name,
        :space_guid,
        :space_name,
        :state,
        Sequel.as(nil, :task_guid),
        Sequel.as(nil, :task_name),
        Sequel.as(:created_at, :updated_at)),
      all: true,
      from_self: false
    ).from_self
  )
  end
end

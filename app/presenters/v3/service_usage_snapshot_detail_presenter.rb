require 'presenters/v3/base_presenter'

module VCAP::CloudController
  module Presenters
    module V3
      class ServiceUsageSnapshotDetailPresenter < BasePresenter
        def to_hash
          {
            organization_guid: detail.organization_guid,
            space_guid: detail.space_guid,
            service_instance_guid: detail.service_instance_guid,
            service_instance_name: detail.service_instance_name,
            service_instance_type: detail.service_instance_type,
            service_plan_guid: detail.service_plan_guid,
            service_plan_name: detail.service_plan_name,
            service_offering_guid: detail.service_offering_guid,
            service_offering_name: detail.service_offering_name,
            service_broker_guid: detail.service_broker_guid,
            service_broker_name: detail.service_broker_name
          }
        end

        private

        def detail
          @resource
        end
      end
    end
  end
end

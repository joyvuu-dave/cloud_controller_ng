require 'fetchers/base_list_fetcher'

module VCAP::CloudController
  class ServiceUsageSnapshotDetailsListFetcher < BaseListFetcher
    class << self
      def fetch_all(message, dataset)
        filter(message, dataset)
      end

      private

      def filter(message, dataset)
        dataset = apply_guid_filter(dataset, message, :organization_guids, :organization_guid)
        dataset = apply_guid_filter(dataset, message, :space_guids, :space_guid)
        dataset = apply_guid_filter(dataset, message, :service_instance_guids, :service_instance_guid)
        dataset = apply_guid_filter(dataset, message, :service_plan_guids, :service_plan_guid)
        dataset = apply_guid_filter(dataset, message, :service_offering_guids, :service_offering_guid)
        dataset = apply_guid_filter(dataset, message, :service_broker_guids, :service_broker_guid)

        super(message, dataset, ServiceUsageSnapshotDetail)
      end

      def apply_guid_filter(dataset, message, message_field, column_name)
        return dataset unless message.requested?(message_field) && message.public_send(message_field).any?

        dataset.where(column_name => message.public_send(message_field))
      end
    end
  end
end

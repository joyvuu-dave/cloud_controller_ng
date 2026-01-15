require 'fetchers/base_list_fetcher'

module VCAP::CloudController
  class AppUsageSnapshotDetailsListFetcher < BaseListFetcher
    class << self
      def fetch_all(message, dataset)
        filter(message, dataset)
      end

      private

      def filter(message, dataset)
        dataset = dataset.where(organization_guid: message.organization_guids) if message.requested?(:organization_guids) && message.organization_guids.any?

        dataset = dataset.where(space_guid: message.space_guids) if message.requested?(:space_guids) && message.space_guids.any?

        super(message, dataset, AppUsageSnapshotDetail)
      end
    end
  end
end

module VCAP::CloudController
  class AppUsageConsumerListFetcher
    def self.fetch_all(message)
      dataset = AppUsageConsumer.dataset
      filter(message, dataset)
    end

    def self.filter(message, dataset)
      dataset = dataset.where(consumer_guid: message.consumer_guids) if message.requested?(:consumer_guids)

      dataset = dataset.where(last_processed_guid: message.last_processed_guids) if message.requested?(:last_processed_guids)

      dataset
    end
  end
end

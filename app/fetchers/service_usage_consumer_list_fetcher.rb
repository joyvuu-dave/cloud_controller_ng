module VCAP::CloudController
  class ServiceUsageConsumerListFetcher
    def self.fetch_all(message)
      dataset = ServiceUsageConsumer.dataset
      filter(message, dataset)
    end

    def self.filter(message, dataset)
      if message.requested?(:consumer_guids)
        dataset = dataset.where(consumer_guid: message.consumer_guids)
      end

      if message.requested?(:last_processed_guids)
        dataset = dataset.where(last_processed_guid: message.last_processed_guids)
      end

      dataset
    end
  end
end

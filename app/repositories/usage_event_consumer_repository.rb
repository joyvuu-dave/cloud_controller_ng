require 'repositories/event_types'

module VCAP::CloudController
  module Repositories
    class UsageEventConsumerRepository
      def create(consumer_guid:, last_event_guid:, model_name:)
        UsageEventConsumer.create(
          consumer_guid:,
          last_event_guid:,
          model_name:
        )
      end

      def find_by_id(id)
        UsageEventConsumer.first(id:)
      end

      def update(id, attributes)
        consumer = find_by_id(id)
        return nil unless consumer

        consumer.update(attributes)
        consumer
      end

      def delete(id)
        consumer = find_by_id(id)
        consumer&.destroy
      end
    end
  end
end

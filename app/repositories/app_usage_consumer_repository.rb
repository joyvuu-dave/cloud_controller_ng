require 'repositories/event_types'

module VCAP::CloudController
  module Repositories
    class AppUsageConsumerRepository
      def create(consumer_id:, last_app_usage_event_id:)
        AppUsageConsumer.create(
          consumer_id:,
          last_app_usage_event_id:
        )
      end

      def find_by_id(id)
        AppUsageConsumer.first(id:)
      end

      def all
        AppUsageConsumer.all
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

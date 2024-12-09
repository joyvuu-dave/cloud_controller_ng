module VCAP::CloudController
  class AppUsageConsumerCreate
    class Error < StandardError
    end

    def self.create(message)
      AppUsageConsumer.create(
        consumer_id: message.consumer_id,
        last_app_usage_event_id: message.last_app_usage_event_id
      )
    rescue Sequel::ValidationFailed => e
      raise Error.new(e.message)
    end
  end
end

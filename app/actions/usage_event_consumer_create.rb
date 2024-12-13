module VCAP::CloudController
  class UsageEventConsumerCreate
    class Error < StandardError
    end

    def self.create(message)
      UsageEventConsumer.create(
        consumer_guid: message.consumer_guid,
        last_event_guid: message.last_event_guid,
        model_name: message.model_name
      )
    rescue Sequel::ValidationFailed => e
      raise Error.new(e.message)
    end
  end
end

require 'messages/base_message'

module VCAP::CloudController
  class AppUsageConsumerUpdateMessage < BaseMessage
    register_allowed_keys [:last_app_usage_event_id]

    validates_with NoAdditionalKeysValidator

    validates :last_app_usage_event_id, presence: true, string: true

    def self.key_requested?(key)
      @requested_keys.include?(key)
    end
  end
end

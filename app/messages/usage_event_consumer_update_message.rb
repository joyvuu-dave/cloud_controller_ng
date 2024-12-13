require 'messages/base_message'

module VCAP::CloudController
  class UsageEventConsumerUpdateMessage < BaseMessage
    register_allowed_keys [:last_event_guid]

    validates_with NoAdditionalKeysValidator

    validates :last_event_guid, presence: true, string: true

    def self.key_requested?(key)
      @requested_keys.include?(key)
    end
  end
end

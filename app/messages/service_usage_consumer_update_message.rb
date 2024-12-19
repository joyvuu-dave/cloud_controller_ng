require 'messages/base_message'
require 'messages/validators'

module VCAP::CloudController
  class ServiceUsageConsumerUpdateMessage < BaseMessage
    register_allowed_keys [:last_processed_guid]

    validates_with NoAdditionalKeysValidator

    validates :last_processed_guid, presence: true, string: true

    def self.key_requested?(key)
      @requested_keys.include?(key)
    end
  end
end

require 'messages/metadata_base_message'
require 'messages/validators'

module VCAP::CloudController
  class ServiceUsageConsumerCreateMessage < MetadataBaseMessage
    register_allowed_keys %i[consumer_guid last_processed_guid]

    validates_with NoAdditionalKeysValidator

    validates :consumer_guid, presence: true, string: true
    validates :last_processed_guid, presence: true, string: true
  end
end

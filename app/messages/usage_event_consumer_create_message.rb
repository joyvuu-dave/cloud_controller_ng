require 'messages/metadata_base_message'
require 'messages/validators'

module VCAP::CloudController
  class UsageEventConsumerCreateMessage < MetadataBaseMessage
    register_allowed_keys %i[consumer_guid last_event_guid model_name]

    validates_with NoAdditionalKeysValidator

    validates :consumer_guid, presence: true, string: true
    validates :last_event_guid, presence: true, string: true
    validates :model_name, presence: true, string: true
  end
end

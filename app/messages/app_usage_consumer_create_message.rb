require 'messages/metadata_base_message'
require 'messages/validators'

module VCAP::CloudController
  class AppUsageConsumerCreateMessage < MetadataBaseMessage
    register_allowed_keys %i[consumer_id last_app_usage_event_id]

    validates_with NoAdditionalKeysValidator

    validates :consumer_id, presence: true, string: true
    validates :last_app_usage_event_id, presence: true, string: true
  end
end

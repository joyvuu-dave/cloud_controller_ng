require 'messages/list_message'

module VCAP::CloudController
  class ServiceUsageConsumersListMessage < ListMessage
    register_allowed_keys [
      :consumer_guids,
      :last_processed_guids
    ]

    validates_with NoUnknownKeysValidator

    validates :consumer_guids, array: true, allow_nil: true
    validates :last_processed_guids, array: true, allow_nil: true

    def self.from_params(params)
      super(params, %w(consumer_guids last_processed_guids))
    end
  end
end

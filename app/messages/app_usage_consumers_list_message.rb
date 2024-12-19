require 'messages/list_message'
require 'messages/validators'

module VCAP::CloudController
  class AppUsageConsumersListMessage < ListMessage
    register_allowed_keys %i[
      consumer_ids
      last_app_usage_event_ids
      page
      per_page
      order_by
    ]

    validates :consumer_ids, array: true, allow_nil: true
    validates :last_app_usage_event_ids, array: true, allow_nil: true

    def self.from_params(params)
      super(params, %w[consumer_ids last_app_usage_event_ids])
    end
  end
end

require 'presenters/v3/base_presenter'

module VCAP::CloudController::Presenters::V3
  class UsageEventConsumerPresenter < BasePresenter
    def to_hash
      {
        guid: usage_event_consumer.guid,
        consumer_guid: usage_event_consumer.consumer_guid,
        last_event_guid: usage_event_consumer.last_event_guid,
        model_name: usage_event_consumer.model_name,
        created_at: usage_event_consumer.created_at,
        updated_at: usage_event_consumer.updated_at,
        links: build_links
      }
    end

    private

    def usage_event_consumer
      @resource
    end

    def build_links
      {
        self: {
          href: url_builder.build_url(path: "/v3/usage_event_consumers/#{usage_event_consumer.guid}")
        }
      }
    end
  end
end

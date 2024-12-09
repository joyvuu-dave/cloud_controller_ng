require 'presenters/v3/base_presenter'

module VCAP::CloudController::Presenters::V3
  class AppUsageConsumerPresenter < BasePresenter
    def to_hash
      {
        guid: app_usage_consumer.guid,
        consumer_id: app_usage_consumer.consumer_id,
        last_app_usage_event_id: app_usage_consumer.last_app_usage_event_id,
        created_at: app_usage_consumer.created_at,
        updated_at: app_usage_consumer.updated_at,
        links: build_links
      }
    end

    private

    def app_usage_consumer
      @resource
    end

    def build_links
      {
        self: {
          href: url_builder.build_url(path: "/v3/app_usage_consumers/#{app_usage_consumer.guid}")
        }
      }
    end
  end
end

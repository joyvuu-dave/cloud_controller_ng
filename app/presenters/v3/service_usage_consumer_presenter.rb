require 'presenters/v3/base_presenter'

module VCAP::CloudController::Presenters::V3
  class ServiceUsageConsumerPresenter < BasePresenter
    def to_hash
      {
        guid: consumer_guid,
        last_processed_guid: last_processed_guid,
        created_at: resource.created_at,
        updated_at: resource.updated_at,
        links: build_links
      }
    end

    private

    def consumer_guid
      resource.consumer_guid
    end

    def last_processed_guid
      resource.last_processed_guid
    end

    def build_links
      url_builder = VCAP::CloudController::Presenters::ApiUrlBuilder.new

      {
        self: {
          href: url_builder.build_url(path: "/v3/service_usage_consumers/#{consumer_guid}")
        }
      }
    end
  end
end

module VCAP::CloudController
  class AppUsageConsumerAccess < BaseAccess
    def index?
      true
    end

    def delete?(_app_usage_consumer)
      true
    end
  end
end

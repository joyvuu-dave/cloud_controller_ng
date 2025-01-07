module VCAP::CloudController
  class AppUsageConsumerAccess < BaseAccess
    def delete?(_app_usage_consumer)
      true
    end
  end
end

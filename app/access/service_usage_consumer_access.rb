module VCAP::CloudController
  class ServiceUsageConsumerAccess < BaseAccess
    def delete?(_service_usage_consumer)
      true
    end
  end
end

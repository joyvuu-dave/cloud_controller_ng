module VCAP::CloudController
  class ServiceUsageConsumerAccess < BaseAccess
    def create?(_service_usage_consumer, _params=nil)
      admin_user?
    end

    def read?(_service_usage_consumer)
      admin_user?
    end

    def update?(_service_usage_consumer, _params=nil)
      admin_user?
    end

    def delete?(_service_usage_consumer)
      admin_user?
    end

    def index?(_service_usage_consumer=nil)
      admin_user?
    end

    def reset?(_service_usage_consumer=nil)
      admin_user?
    end

    private

    def admin_user?
      context.roles.admin?
    end
  end
end

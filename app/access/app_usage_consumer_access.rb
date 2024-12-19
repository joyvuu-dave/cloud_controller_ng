module VCAP::CloudController
  class AppUsageConsumerAccess < BaseAccess
    def create?(_app_usage_consumer, _params=nil)
      admin_user?
    end

    def read?(_app_usage_consumer)
      admin_user?
    end

    def update?(_app_usage_consumer, _params=nil)
      admin_user?
    end

    def delete?(_app_usage_consumer)
      admin_user?
    end

    def index?(_app_usage_consumer=nil)
      admin_user?
    end

    def reset?(_app_usage_consumer=nil)
      admin_user?
    end

    private

    def admin_user?
      context.roles.admin?
    end
  end
end

module VCAP::CloudController
  class UsageEventConsumerAccess < BaseAccess
    def create?(_usage_event_consumer, _params=nil)
      admin_user?
    end

    def read?(_usage_event_consumer)
      admin_user?
    end

    def update?(_usage_event_consumer, _params=nil)
      admin_user?
    end

    def delete?(_usage_event_consumer)
      admin_user?
    end

    def reset?(_usage_event_consumer=nil)
      admin_user?
    end

    private

    def admin_user?
      context.roles.admin?
    end
  end
end

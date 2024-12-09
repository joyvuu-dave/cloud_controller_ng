module VCAP::CloudController
    class AppUsageConsumerAccess < BaseAccess
      def create?(app_usage_consumer, params=nil)
        admin_user?
      end
  
      def read?(app_usage_consumer)
        admin_user?
      end
  
      def update?(app_usage_consumer, params=nil)
        admin_user?
      end
  
      def delete?(app_usage_consumer)
        admin_user?
      end
  
      def index?(app_usage_consumer=nil)
        admin_user?
      end
  
      def reset?(app_usage_consumer=nil)
        admin_user?
      end
  
      private
  
      def admin_user?
        context.roles.admin?
      end
    end
  end
  
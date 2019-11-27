
module Kpack
  class Stager
    def stage(staging_details)
      client.create_build(staging_details)
    end

    def stop_stage
      raise NoMethodError
    end

    def staging_complete
      raise NoMethodError
    end

    private

    def client
      ::CloudController::DependencyLocator.instance.kpack_client
    end
  end
end

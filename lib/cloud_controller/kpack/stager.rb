
module Kpack
  class Stager
    def stage(staging_details)
      build = Kubeclient::Resource.new
      build.metadata = {
        name: staging_details.staging_guid,
        namespace: 'cf-workloads',
      }
      build.spec = {
        builder: {
          image: 'cloudfoundry/cnb:bionic'
        },
        source: {
          blob: {
            url: blobstore_url_generator.package_download_url(staging_details.package),
          },
        },
      }
      client.create_build(build)
    end

    def stop_stage
      raise NoMethodError
    end

    def staging_complete
      raise NoMethodError
    end

    private

    def build_resource(staging_details)
      Kubeclient::Resource.new
    end
    def client
      ::CloudController::DependencyLocator.instance.kpack_client
    end

    def blobstore_url_generator
      ::CloudController::DependencyLocator.instance.blobstore_url_generator
    end
  end
end

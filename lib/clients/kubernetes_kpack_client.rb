require 'clients/kubernetes_client'

module Clients
  class KubernetesKpackClient
    attr_reader :client

    # TODO: fix BOSH release to take hostname instead of api uri
    def initialize(hostname:, service_account:, ca_crt:)
      raise KubernetesClient::InvalidURIError if hostname.empty?

      @client = KubernetesClient.new(
        api_uri: "#{hostname}/apis/build.pivotal.io",
        version: 'v1alpha1',
        service_account: service_account,
        ca_crt: ca_crt,
      ).client
    end

    def create_build(*args)
      client.create_build(*args)
    end
  end
end

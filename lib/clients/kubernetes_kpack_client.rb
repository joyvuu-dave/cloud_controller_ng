require 'clients/kubernetes_client'

module Clients
  class KubernetesKpackClient
    attr_reader :client

    def initialize(hostname:, service_account:, ca_crt:)
      raise KubernetesClient::InvalidURIError if hostname.empty?

      @client = KubernetesClient.new(
        api_uri: "#{hostname}/apis/build.pivotal.io",
        version: 'v1alpha1',
        service_account: service_account,
        ca_crt: ca_crt,
      ).client
    end
  end
end
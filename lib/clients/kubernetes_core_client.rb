require 'clients/kubernetes_client'

module Clients
  class KubernetesCoreClient
    attr_reader :client

    def initialize(hostname:, service_account:, ca_crt:)
      @client = KubernetesClient.new(
        api_uri: "#{hostname}/apis/core",
        version: 'v1',
        service_account: service_account,
        ca_crt: ca_crt,
      ).client
    end
  end
end
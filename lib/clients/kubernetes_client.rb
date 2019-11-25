require 'kubeclient'

module Clients
  class KubernetesClient
    class MissingCredentialsError < StandardError; end

    attr_reader :v1_client, :kpack_client, :apps_client

    def initialize(host_url:, service_account:, ca_crt:)
      if [host_url, service_account, ca_crt].any?(&:blank?)
        raise MissingCredentialsError.new('Missing credentials for Kubernetes')
      end

      auth_options = {
        bearer_token: service_account[:token]
      }
      ssl_options = {
        ca: ca_crt
      }
      @v1_client = Kubeclient::Client.new(
        host_url,
        'v1',
        auth_options: auth_options,
        ssl_options:  ssl_options
      )
      @kpack_client = Kubeclient::Client.new(
        "#{host_url}/apis/build.pivotal.io",
        'v1alpha1',
        auth_options: auth_options,
        ssl_options:  ssl_options
      )
      @apps_client = Kubeclient::Client.new(
        "#{host_url}/apis/apps",
        'v1',
        auth_options: auth_options,
        ssl_options:  ssl_options
      )
    end
  end
end

require 'spec_helper'
require 'clients/kubernetes_client'

RSpec.describe Clients::KubernetesClient do
  before do
    TestConfig.override(
      kubernetes: {
        url: "my_kubernetes.io/api",
        service_account: {
          name: "username",
          token: "token",
        },
        ca: "k8s_node_ca"
      }
    )
  end

  it 'loads kubernetes creds from the config' do
    client = Clients::KubernetesClient.new.client

    expect(client.ssl_options).to eq({
      ca: "k8s_node_ca"
    })

    expect(client.auth_options).to eq({
      bearer_token: "token"
    })

    expect(client.api_endpoint.to_s).to eq "my_kubernetes.io/api"
  end

end

require 'spec_helper'
require 'clients/kubernetes_core_client'

RSpec.describe Clients::KubernetesCoreClient do
  let(:kubernetes_creds) do
    {
      hostname: 'my.kubernetes.io',
      service_account: {
        name: 'username',
        token: 'token',
      },
      ca_crt: 'k8s_node_ca'
    }
  end

  it 'loads kubernetes creds from the config' do
    client = Clients::KubernetesCoreClient.new(kubernetes_creds).client

    expect(client.ssl_options).to eq({
      ca: 'k8s_node_ca'
    })

    expect(client.auth_options).to eq({
      bearer_token: 'token'
    })

    expect(client.api_endpoint.to_s).to eq 'https://my.kubernetes.io/apis/core'
  end
end

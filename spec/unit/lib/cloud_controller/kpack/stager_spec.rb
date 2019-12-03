require 'spec_helper'
require 'cloud_controller/kpack/stager'
require 'clients/kubernetes_kpack_client'

module Kpack
  RSpec.describe Stager do
    subject(:stager) {Stager.new}
    let(:package) {VCAP::CloudController::PackageModel.make}
    let(:environment_variables) {{'nightshade_vegetable' => 'potato'}}
    let(:staging_memory_in_mb) {1024}
    let(:staging_disk_in_mb) {1024}
    let(:blobstore_url_generator) do
      instance_double(::CloudController::Blobstore::UrlGenerator,
        package_download_url: 'package-download-url',
      )
    end
    let(:client) { instance_double(Clients::KubernetesKpackClient) }
    before do
      allow(CloudController::DependencyLocator.instance).to receive(:kpack_client).and_return(client)
      allow(CloudController::DependencyLocator.instance).to receive(:blobstore_url_generator).and_return(blobstore_url_generator)
    end


    it_behaves_like 'a stager'

    describe '#stage' do
      let(:staging_details) do
        details = VCAP::CloudController::Diego::StagingDetails.new
        details.package = package
        details.environment_variables = environment_variables
        details.staging_memory_in_mb = staging_memory_in_mb
        details.staging_disk_in_mb = staging_disk_in_mb
        details.staging_guid = build.guid
        details.lifecycle = lifecycle
        details
      end
      let(:lifecycle) do
        VCAP::CloudController::KpackLifecycle.new(package, {})
      end
      let(:build) {VCAP::CloudController::BuildModel.make(:kpack)}

      it 'creates a build using the kpack client' do
        expect(client).to receive(:create_build)
        stager.stage(staging_details)
      end
    end
  end
end

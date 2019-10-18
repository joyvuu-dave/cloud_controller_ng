require 'spec_helper'

module VCAP::CloudController
  RSpec.describe ClusterModel do
    let(:space) { Space.make }
    let(:process) { ProcessModel.make }
    let!(:cluster) { ClusterModel.create(name: 'default', url: 'some.eirini.biz', space: space) }
    let!(:placement) { PlacementModel.create(name: 'default', space: space) }

    it 'goes through the paces' do
      PlacementSplitModel.create(weight: 2, placement: placement, cluster: cluster)
      PlacementSplitModel.create(weight: 1, placement: placement, cluster: cluster)
      PlacementBindingModel.create(placement: placement, process: process)
    end
  end
end

require 'spec_helper'

module VCAP::CloudController
  RSpec.describe ServiceUsageSnapshotDetail do
    subject(:detail) { ServiceUsageSnapshotDetail.make }

    describe 'associations' do
      it 'belongs to a service_usage_snapshot' do
        snapshot = ServiceUsageSnapshot.make
        detail = ServiceUsageSnapshotDetail.make(service_usage_snapshot: snapshot)

        expect(detail.service_usage_snapshot).to eq(snapshot)
      end
    end

    describe 'validations' do
      it 'validates presence of snapshot_id' do
        detail.snapshot_id = nil
        expect(detail).not_to be_valid
        expect(detail.errors[:snapshot_id]).to include("can't be blank")
      end

      it 'validates presence of organization_guid' do
        detail.organization_guid = nil
        expect(detail).not_to be_valid
        expect(detail.errors[:organization_guid]).to include("can't be blank")
      end

      it 'validates presence of space_guid' do
        detail.space_guid = nil
        expect(detail).not_to be_valid
        expect(detail.errors[:space_guid]).to include("can't be blank")
      end

      it 'validates presence of service_instance_guid' do
        detail.service_instance_guid = nil
        expect(detail).not_to be_valid
        expect(detail.errors[:service_instance_guid]).to include("can't be blank")
      end

      it 'validates presence of service_instance_name' do
        detail.service_instance_name = nil
        expect(detail).not_to be_valid
        expect(detail.errors[:service_instance_name]).to include("can't be blank")
      end

      it 'validates presence of service_instance_type' do
        detail.service_instance_type = nil
        expect(detail).not_to be_valid
        expect(detail.errors[:service_instance_type]).to include("can't be blank")
      end
    end
  end
end

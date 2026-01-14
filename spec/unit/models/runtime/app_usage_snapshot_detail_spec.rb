require 'spec_helper'

module VCAP::CloudController
  RSpec.describe AppUsageSnapshotDetail do
    subject(:detail) { AppUsageSnapshotDetail.make }

    describe 'associations' do
      it 'belongs to a app_usage_snapshot' do
        snapshot = UsageSnapshot.make
        detail = AppUsageSnapshotDetail.make(app_usage_snapshot: snapshot)

        expect(detail.app_usage_snapshot).to eq(snapshot)
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

      it 'validates presence of app_guid' do
        detail.app_guid = nil
        expect(detail).not_to be_valid
        expect(detail.errors[:app_guid]).to include("can't be blank")
      end

      it 'validates presence of process_guid' do
        detail.process_guid = nil
        expect(detail).not_to be_valid
        expect(detail.errors[:process_guid]).to include("can't be blank")
      end

      it 'validates presence of process_type' do
        detail.process_type = nil
        expect(detail).not_to be_valid
        expect(detail.errors[:process_type]).to include("can't be blank")
      end

      it 'validates presence of instances' do
        detail.instances = nil
        expect(detail).not_to be_valid
        expect(detail.errors[:instances]).to include("can't be blank")
      end
    end
  end
end

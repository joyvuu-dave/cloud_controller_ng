require 'spec_helper'

module VCAP::CloudController
  RSpec.describe ServiceUsageSnapshotDetail do
    describe 'associations' do
      it 'belongs to a service_usage_snapshot' do
        snapshot = ServiceUsageSnapshot.make
        snapshot.save

        detail = ServiceUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          space_guid: 'space-guid',
          service_instance_guid: 'si-guid',
          service_instance_name: 'si-name',
          service_instance_type: 'managed_service_instance'
        )
        detail.save

        expect(detail.service_usage_snapshot).to eq(snapshot)
      end
    end

    describe 'validations' do
      it 'validates presence of snapshot_id' do
        detail = ServiceUsageSnapshotDetail.new(
          organization_guid: 'org-guid',
          space_guid: 'space-guid',
          service_instance_guid: 'si-guid',
          service_instance_name: 'si-name',
          service_instance_type: 'managed_service_instance'
        )
        detail.validate
        expect(detail.errors.on(:snapshot_id)).to eq([:presence])
      end

      it 'allows nil organization_guid (for deleted orgs)' do
        snapshot = ServiceUsageSnapshot.make
        snapshot.save

        detail = ServiceUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: nil,
          space_guid: 'space-guid',
          service_instance_guid: 'si-guid',
          service_instance_name: 'si-name',
          service_instance_type: 'managed_service_instance'
        )
        expect(detail).to be_valid
      end

      it 'allows nil space_guid (for deleted spaces)' do
        snapshot = ServiceUsageSnapshot.make
        snapshot.save

        detail = ServiceUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          space_guid: nil,
          service_instance_guid: 'si-guid',
          service_instance_name: 'si-name',
          service_instance_type: 'managed_service_instance'
        )
        expect(detail).to be_valid
      end

      it 'validates presence of service_instance_guid' do
        snapshot = ServiceUsageSnapshot.make
        snapshot.save

        detail = ServiceUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          space_guid: 'space-guid',
          service_instance_guid: nil,
          service_instance_name: 'si-name',
          service_instance_type: 'managed_service_instance'
        )
        detail.validate
        expect(detail.errors.on(:service_instance_guid)).to eq([:presence])
      end

      it 'validates presence of service_instance_name' do
        snapshot = ServiceUsageSnapshot.make
        snapshot.save

        detail = ServiceUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          space_guid: 'space-guid',
          service_instance_guid: 'si-guid',
          service_instance_name: nil,
          service_instance_type: 'managed_service_instance'
        )
        detail.validate
        expect(detail.errors.on(:service_instance_name)).to eq([:presence])
      end

      it 'validates presence of service_instance_type' do
        snapshot = ServiceUsageSnapshot.make
        snapshot.save

        detail = ServiceUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          space_guid: 'space-guid',
          service_instance_guid: 'si-guid',
          service_instance_name: 'si-name',
          service_instance_type: nil
        )
        detail.validate
        expect(detail.errors.on(:service_instance_type)).to eq([:presence])
      end
    end
  end
end

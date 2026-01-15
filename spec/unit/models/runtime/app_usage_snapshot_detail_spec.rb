require 'spec_helper'

module VCAP::CloudController
  RSpec.describe AppUsageSnapshotDetail do
    describe 'associations' do
      it 'belongs to a app_usage_snapshot' do
        snapshot = AppUsageSnapshot.make
        snapshot.save

        detail = AppUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          space_guid: 'space-guid',
          app_guid: 'app-guid',
          process_guid: 'process-guid',
          process_type: 'web',
          instances: 1
        )
        detail.save

        expect(detail.app_usage_snapshot).to eq(snapshot)
      end
    end

    describe 'validations' do
      it 'validates presence of snapshot_id' do
        detail = AppUsageSnapshotDetail.new(
          organization_guid: 'org-guid',
          space_guid: 'space-guid',
          app_guid: 'app-guid',
          process_guid: 'process-guid',
          process_type: 'web',
          instances: 1
        )
        detail.validate
        expect(detail.errors.on(:snapshot_id)).to eq([:presence])
      end

      it 'allows nil organization_guid (for deleted orgs)' do
        snapshot = AppUsageSnapshot.make
        snapshot.save

        detail = AppUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: nil,
          space_guid: 'space-guid',
          app_guid: 'app-guid',
          process_guid: 'process-guid',
          process_type: 'web',
          instances: 1
        )
        expect(detail).to be_valid
      end

      it 'allows nil space_guid (for deleted spaces)' do
        snapshot = AppUsageSnapshot.make
        snapshot.save

        detail = AppUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          space_guid: nil,
          app_guid: 'app-guid',
          process_guid: 'process-guid',
          process_type: 'web',
          instances: 1
        )
        expect(detail).to be_valid
      end

      it 'validates presence of app_guid' do
        snapshot = AppUsageSnapshot.make
        snapshot.save

        detail = AppUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          space_guid: 'space-guid',
          app_guid: nil,
          process_guid: 'process-guid',
          process_type: 'web',
          instances: 1
        )
        detail.validate
        expect(detail.errors.on(:app_guid)).to eq([:presence])
      end

      it 'validates presence of process_guid' do
        snapshot = AppUsageSnapshot.make
        snapshot.save

        detail = AppUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          space_guid: 'space-guid',
          app_guid: 'app-guid',
          process_guid: nil,
          process_type: 'web',
          instances: 1
        )
        detail.validate
        expect(detail.errors.on(:process_guid)).to eq([:presence])
      end

      it 'validates presence of process_type' do
        snapshot = AppUsageSnapshot.make
        snapshot.save

        detail = AppUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          space_guid: 'space-guid',
          app_guid: 'app-guid',
          process_guid: 'process-guid',
          process_type: nil,
          instances: 1
        )
        detail.validate
        expect(detail.errors.on(:process_type)).to eq([:presence])
      end

      it 'validates presence of instances' do
        snapshot = AppUsageSnapshot.make
        snapshot.save

        detail = AppUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          space_guid: 'space-guid',
          app_guid: 'app-guid',
          process_guid: 'process-guid',
          process_type: 'web',
          instances: nil
        )
        detail.validate
        expect(detail.errors.on(:instances)).to eq([:presence])
      end
    end
  end
end

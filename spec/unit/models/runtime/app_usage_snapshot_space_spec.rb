require 'spec_helper'

module VCAP::CloudController
  RSpec.describe AppUsageSnapshotSpace do
    describe 'associations' do
      it 'belongs to app_usage_snapshot' do
        snapshot = AppUsageSnapshot.make
        space = AppUsageSnapshotSpace.make(app_usage_snapshot: snapshot)

        expect(space.app_usage_snapshot).to eq(snapshot)
      end
    end

    describe 'validations' do
      it 'validates presence of app_usage_snapshot_id' do
        space = AppUsageSnapshotSpace.new(
          space_guid: 'space-guid',
          organization_guid: 'org-guid',
          instance_count: 0
        )
        space.validate
        expect(space.errors.on(:app_usage_snapshot_id)).to eq([:presence])
      end

      it 'validates presence of space_guid' do
        snapshot = AppUsageSnapshot.make
        space = AppUsageSnapshotSpace.new(
          app_usage_snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          instance_count: 0
        )
        space.validate
        expect(space.errors.on(:space_guid)).to eq([:presence])
      end

      it 'validates presence of organization_guid' do
        snapshot = AppUsageSnapshot.make
        space = AppUsageSnapshotSpace.new(
          app_usage_snapshot_id: snapshot.id,
          space_guid: 'space-guid',
          instance_count: 0
        )
        space.validate
        expect(space.errors.on(:organization_guid)).to eq([:presence])
      end

      it 'validates presence of instance_count' do
        snapshot = AppUsageSnapshot.make
        space = AppUsageSnapshotSpace.new(
          app_usage_snapshot_id: snapshot.id,
          space_guid: 'space-guid',
          organization_guid: 'org-guid'
        )
        space.validate
        expect(space.errors.on(:instance_count)).to eq([:presence])
      end
    end

    describe 'processes serialization' do
      it 'serializes and deserializes processes as JSON' do
        snapshot = AppUsageSnapshot.make
        processes = [
          { 'app_guid' => 'app-1', 'process_type' => 'web', 'instances' => 3 },
          { 'app_guid' => 'app-2', 'process_type' => 'worker', 'instances' => 2 }
        ]

        space = AppUsageSnapshotSpace.create(
          app_usage_snapshot_id: snapshot.id,
          space_guid: 'space-guid',
          organization_guid: 'org-guid',
          instance_count: 5,
          processes: processes
        )

        space.reload
        expect(space.processes).to eq(processes)
      end

      it 'handles nil processes' do
        snapshot = AppUsageSnapshot.make
        space = AppUsageSnapshotSpace.create(
          app_usage_snapshot_id: snapshot.id,
          space_guid: 'space-guid',
          organization_guid: 'org-guid',
          instance_count: 0,
          processes: nil
        )

        space.reload
        expect(space.processes).to be_nil
      end
    end

    describe 'cascade delete' do
      it 'deletes space records when snapshot is deleted' do
        snapshot = AppUsageSnapshot.make
        AppUsageSnapshotSpace.make(app_usage_snapshot: snapshot, space_guid: 'space-1')
        AppUsageSnapshotSpace.make(app_usage_snapshot: snapshot, space_guid: 'space-2')

        expect(AppUsageSnapshotSpace.count).to eq(2)

        snapshot.destroy

        expect(AppUsageSnapshotSpace.count).to eq(0)
      end
    end
  end
end

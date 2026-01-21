require 'spec_helper'

module VCAP::CloudController
  RSpec.describe ServiceUsageSnapshotSpace do
    describe 'associations' do
      it 'belongs to service_usage_snapshot' do
        snapshot = ServiceUsageSnapshot.make
        space = ServiceUsageSnapshotSpace.make(service_usage_snapshot: snapshot)

        expect(space.service_usage_snapshot).to eq(snapshot)
      end
    end

    describe 'validations' do
      it 'validates presence of service_usage_snapshot_id' do
        space = ServiceUsageSnapshotSpace.new(
          space_guid: 'space-guid',
          organization_guid: 'org-guid',
          service_instance_count: 0
        )
        space.validate
        expect(space.errors.on(:service_usage_snapshot_id)).to eq([:presence])
      end

      it 'validates presence of space_guid' do
        snapshot = ServiceUsageSnapshot.make
        space = ServiceUsageSnapshotSpace.new(
          service_usage_snapshot_id: snapshot.id,
          organization_guid: 'org-guid',
          service_instance_count: 0
        )
        space.validate
        expect(space.errors.on(:space_guid)).to eq([:presence])
      end

      it 'validates presence of organization_guid' do
        snapshot = ServiceUsageSnapshot.make
        space = ServiceUsageSnapshotSpace.new(
          service_usage_snapshot_id: snapshot.id,
          space_guid: 'space-guid',
          service_instance_count: 0
        )
        space.validate
        expect(space.errors.on(:organization_guid)).to eq([:presence])
      end

      it 'validates presence of service_instance_count' do
        snapshot = ServiceUsageSnapshot.make
        space = ServiceUsageSnapshotSpace.new(
          service_usage_snapshot_id: snapshot.id,
          space_guid: 'space-guid',
          organization_guid: 'org-guid'
        )
        space.validate
        expect(space.errors.on(:service_instance_count)).to eq([:presence])
      end
    end

    describe 'service_instances serialization' do
      it 'serializes and deserializes service_instances as JSON' do
        snapshot = ServiceUsageSnapshot.make
        service_instances = [
          { 'guid' => 'si-1', 'name' => 'my-db', 'type' => 'managed' },
          { 'guid' => 'si-2', 'name' => 'my-cache', 'type' => 'user_provided' }
        ]

        space = ServiceUsageSnapshotSpace.create(
          service_usage_snapshot_id: snapshot.id,
          space_guid: 'space-guid',
          organization_guid: 'org-guid',
          service_instance_count: 2,
          service_instances: service_instances
        )

        space.reload
        expect(space.service_instances).to eq(service_instances)
      end

      it 'handles nil service_instances' do
        snapshot = ServiceUsageSnapshot.make
        space = ServiceUsageSnapshotSpace.create(
          service_usage_snapshot_id: snapshot.id,
          space_guid: 'space-guid',
          organization_guid: 'org-guid',
          service_instance_count: 0,
          service_instances: nil
        )

        space.reload
        expect(space.service_instances).to be_nil
      end
    end

    describe 'cascade delete' do
      it 'deletes space records when snapshot is deleted' do
        snapshot = ServiceUsageSnapshot.make
        ServiceUsageSnapshotSpace.make(service_usage_snapshot: snapshot, space_guid: 'space-1')
        ServiceUsageSnapshotSpace.make(service_usage_snapshot: snapshot, space_guid: 'space-2')

        expect(ServiceUsageSnapshotSpace.count).to eq(2)

        snapshot.destroy

        expect(ServiceUsageSnapshotSpace.count).to eq(0)
      end
    end
  end
end

require 'spec_helper'

module VCAP::CloudController
  RSpec.describe ServiceUsageSnapshot do
    describe 'associations' do
      it 'has many service_usage_snapshot_details' do
        snapshot = ServiceUsageSnapshot.make
        snapshot.save

        detail1 = ServiceUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid-1',
          space_guid: 'space-guid-1',
          service_instance_guid: 'si-guid-1',
          service_instance_name: 'si-name-1',
          service_instance_type: 'managed_service_instance'
        )
        detail1.save

        detail2 = ServiceUsageSnapshotDetail.new(
          snapshot_id: snapshot.id,
          organization_guid: 'org-guid-2',
          space_guid: 'space-guid-2',
          service_instance_guid: 'si-guid-2',
          service_instance_name: 'si-name-2',
          service_instance_type: 'user_provided'
        )
        detail2.save

        expect(snapshot.service_usage_snapshot_details).to contain_exactly(detail1, detail2)
      end
    end

    describe 'validations' do
      it 'validates presence of guid' do
        snapshot = ServiceUsageSnapshot.new(
          created_at: Time.now.utc,
          service_instance_count: 0,
          organization_count: 0,
          space_count: 0
        )
        snapshot.guid = nil
        snapshot.validate
        expect(snapshot.errors.on(:guid)).to eq([:presence])
      end

      it 'allows nil checkpoint_event_id (for placeholder snapshots)' do
        snapshot = ServiceUsageSnapshot.make
        snapshot.checkpoint_event_id = nil
        expect(snapshot).to be_valid
      end

      it 'validates presence of created_at' do
        snapshot = ServiceUsageSnapshot.new(
          guid: SecureRandom.uuid,
          service_instance_count: 0,
          organization_count: 0,
          space_count: 0
        )
        snapshot.created_at = nil
        snapshot.validate
        expect(snapshot.errors.on(:created_at)).to eq([:presence])
      end
    end

    describe 'after_initialize' do
      it 'generates a guid if not provided' do
        snapshot = ServiceUsageSnapshot.new(
          checkpoint_event_id: nil,
          created_at: Time.now.utc,
          service_instance_count: 0,
          organization_count: 0,
          space_count: 0
        )
        expect(snapshot.guid).not_to be_nil
        expect(snapshot.guid).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
      end
    end

    describe '#processing?' do
      it 'returns true when completed_at is nil' do
        snapshot = ServiceUsageSnapshot.make
        snapshot.completed_at = nil
        expect(snapshot.processing?).to be true
      end

      it 'returns false when completed_at is set' do
        snapshot = ServiceUsageSnapshot.make
        snapshot.completed_at = Time.now.utc
        expect(snapshot.processing?).to be false
      end
    end

    describe '#complete?' do
      it 'returns false when completed_at is nil' do
        snapshot = ServiceUsageSnapshot.make
        snapshot.completed_at = nil
        expect(snapshot.complete?).to be false
      end

      it 'returns true when completed_at is set' do
        snapshot = ServiceUsageSnapshot.make
        snapshot.completed_at = Time.now.utc
        expect(snapshot.complete?).to be true
      end
    end
  end
end

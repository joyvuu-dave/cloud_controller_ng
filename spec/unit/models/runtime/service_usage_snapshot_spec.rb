require 'spec_helper'

module VCAP::CloudController
  RSpec.describe ServiceUsageSnapshot do
    subject(:snapshot) { ServiceUsageSnapshot.make }

    describe 'associations' do
      it 'has many service_usage_snapshot_details' do
        detail1 = ServiceUsageSnapshotDetail.make(service_usage_snapshot: snapshot)
        detail2 = ServiceUsageSnapshotDetail.make(service_usage_snapshot: snapshot)

        expect(snapshot.service_usage_snapshot_details).to contain_exactly(detail1, detail2)
      end
    end

    describe 'validations' do
      it 'validates presence of guid' do
        snapshot.guid = nil
        expect(snapshot).not_to be_valid
        expect(snapshot.errors[:guid]).to include("can't be blank")
      end

      it 'validates presence of checkpoint_event_id' do
        snapshot.checkpoint_event_id = nil
        expect(snapshot).not_to be_valid
        expect(snapshot.errors[:checkpoint_event_id]).to include("can't be blank")
      end

      it 'validates presence of created_at' do
        snapshot.created_at = nil
        expect(snapshot).not_to be_valid
        expect(snapshot.errors[:created_at]).to include("can't be blank")
      end
    end

    describe 'before_create' do
      it 'generates a guid if not provided' do
        snapshot = ServiceUsageSnapshot.create(checkpoint_event_id: 0, created_at: Time.now.utc)
        expect(snapshot.guid).not_to be_nil
        expect(snapshot.guid).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
      end
    end

    describe '#processing?' do
      it 'returns true when completed_at is nil' do
        snapshot.completed_at = nil
        expect(snapshot.processing?).to be true
      end

      it 'returns false when completed_at is set' do
        snapshot.completed_at = Time.now.utc
        expect(snapshot.processing?).to be false
      end
    end

    describe '#complete?' do
      it 'returns false when completed_at is nil' do
        snapshot.completed_at = nil
        expect(snapshot.complete?).to be false
      end

      it 'returns true when completed_at is set' do
        snapshot.completed_at = Time.now.utc
        expect(snapshot.complete?).to be true
      end
    end
  end
end

require 'spec_helper'

module VCAP::CloudController
  RSpec.describe AppUsageSnapshot do
    describe 'associations' do
      it 'has many app_usage_snapshot_chunks' do
        snapshot = AppUsageSnapshot.make
        chunk1 = AppUsageSnapshotChunk.make(app_usage_snapshot: snapshot, space_guid: 'space-1', chunk_index: 0)
        chunk2 = AppUsageSnapshotChunk.make(app_usage_snapshot: snapshot, space_guid: 'space-2', chunk_index: 0)

        expect(snapshot.app_usage_snapshot_chunks).to contain_exactly(chunk1, chunk2)
      end
    end

    describe 'validations' do
      it 'validates presence of guid' do
        snapshot = AppUsageSnapshot.new(
          created_at: Time.now.utc,
          instance_count: 0,
          organization_count: 0,
          space_count: 0,
          process_count: 0,
          chunk_count: 0
        )
        snapshot.guid = nil
        snapshot.validate
        expect(snapshot.errors.on(:guid)).to eq([:presence])
      end

      it 'allows nil checkpoint_event_id (for placeholder snapshots)' do
        snapshot = AppUsageSnapshot.make
        snapshot.checkpoint_event_id = nil
        expect(snapshot).to be_valid
      end

      it 'validates presence of created_at' do
        snapshot = AppUsageSnapshot.new(
          guid: SecureRandom.uuid,
          instance_count: 0,
          organization_count: 0,
          space_count: 0,
          process_count: 0,
          chunk_count: 0
        )
        snapshot.created_at = nil
        snapshot.validate
        expect(snapshot.errors.on(:created_at)).to eq([:presence])
      end

      it 'validates presence of process_count' do
        snapshot = AppUsageSnapshot.new(
          guid: SecureRandom.uuid,
          created_at: Time.now.utc,
          instance_count: 0,
          organization_count: 0,
          space_count: 0,
          chunk_count: 0
        )
        snapshot.process_count = nil
        snapshot.validate
        expect(snapshot.errors.on(:process_count)).to eq([:presence])
      end

      it 'validates presence of chunk_count' do
        snapshot = AppUsageSnapshot.new(
          guid: SecureRandom.uuid,
          created_at: Time.now.utc,
          instance_count: 0,
          organization_count: 0,
          space_count: 0,
          process_count: 0
        )
        snapshot.chunk_count = nil
        snapshot.validate
        expect(snapshot.errors.on(:chunk_count)).to eq([:presence])
      end
    end

    describe 'after_initialize' do
      it 'generates a guid if not provided' do
        snapshot = AppUsageSnapshot.new(
          checkpoint_event_id: nil,
          created_at: Time.now.utc,
          instance_count: 0,
          organization_count: 0,
          space_count: 0,
          process_count: 0,
          chunk_count: 0
        )
        expect(snapshot.guid).not_to be_nil
        expect(snapshot.guid).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
      end
    end

    describe '#processing?' do
      it 'returns true when completed_at is nil' do
        snapshot = AppUsageSnapshot.make
        snapshot.completed_at = nil
        expect(snapshot.processing?).to be true
      end

      it 'returns false when completed_at is set' do
        snapshot = AppUsageSnapshot.make
        snapshot.completed_at = Time.now.utc
        expect(snapshot.processing?).to be false
      end
    end

    describe '#complete?' do
      it 'returns false when completed_at is nil' do
        snapshot = AppUsageSnapshot.make
        snapshot.completed_at = nil
        expect(snapshot.complete?).to be false
      end

      it 'returns true when completed_at is set' do
        snapshot = AppUsageSnapshot.make
        snapshot.completed_at = Time.now.utc
        expect(snapshot.complete?).to be true
      end
    end
  end
end

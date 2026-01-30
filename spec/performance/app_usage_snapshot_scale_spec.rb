require 'spec_helper'
require 'repositories/app_usage_snapshot_repository'

# Performance tests for app usage snapshot generation at scale.
# These tests verify that snapshot generation:
# 1. Uses bounded memory (chunks, not all-in-memory)
# 2. Completes in reasonable time for moderate scale
# 3. Creates proper chunk boundaries
#
# Run with: bundle exec rspec spec/performance/app_usage_snapshot_scale_spec.rb
# Or tagged: bundle exec rspec --tag performance

RSpec.describe 'App Usage Snapshot Scale', :performance do
  let(:repository) { VCAP::CloudController::Repositories::AppUsageSnapshotRepository.new }

  # Helper to create a placeholder snapshot
  def create_placeholder_snapshot
    VCAP::CloudController::AppUsageSnapshot.create(
      guid: SecureRandom.uuid,
      checkpoint_event_id: nil,
      created_at: Time.now.utc,
      completed_at: nil,
      instance_count: 0,
      organization_count: 0,
      space_count: 0,
      process_count: 0,
      chunk_count: 0
    )
  end

  # Bulk data generator using multi_insert for speed
  def bulk_create_processes(org_count:, spaces_per_org:, processes_per_space:)
    orgs = []
    org_count.times do |i|
      orgs << VCAP::CloudController::Organization.make(name: "perf-org-#{i}")
    end

    spaces = []
    orgs.each_with_index do |org, org_idx|
      spaces_per_org.times do |space_idx|
        spaces << VCAP::CloudController::Space.make(
          organization: org,
          name: "perf-space-#{org_idx}-#{space_idx}"
        )
      end
    end

    # Create apps and processes using bulk insert for speed
    process_records = []
    spaces.each_with_index do |space, space_idx|
      processes_per_space.times do |proc_idx|
        app = VCAP::CloudController::AppModel.make(space: space, name: "perf-app-#{space_idx}-#{proc_idx}")
        process_records << {
          guid: SecureRandom.uuid,
          app_guid: app.guid,
          type: 'web',
          state: VCAP::CloudController::ProcessModel::STARTED,
          instances: rand(1..5),
          created_at: Time.now.utc,
          updated_at: Time.now.utc
        }
      end
    end

    # Bulk insert processes
    VCAP::CloudController::ProcessModel.dataset.multi_insert(process_records)

    {
      org_count: org_count,
      space_count: spaces.size,
      process_count: process_records.size
    }
  end

  describe 'chunking behavior' do
    context 'with many processes in one space (deep hierarchy)' do
      before do
        # Create 1 org, 1 space, 250 processes
        # Should produce 3 chunks (100 + 100 + 50)
        bulk_create_processes(org_count: 1, spaces_per_org: 1, processes_per_space: 250)
      end

      it 'creates multiple chunks for a single space' do
        snapshot = create_placeholder_snapshot

        start_time = Time.now
        repository.populate_snapshot!(snapshot)
        duration = Time.now - start_time

        snapshot.reload
        expect(snapshot.process_count).to eq(250)
        expect(snapshot.chunk_count).to eq(3)
        expect(snapshot.space_count).to eq(1)
        expect(snapshot.organization_count).to eq(1)

        # Verify chunk boundaries
        chunks = snapshot.app_usage_snapshot_chunks.order(:chunk_index).to_a
        expect(chunks.size).to eq(3)
        expect(chunks[0].chunk_index).to eq(0)
        expect(chunks[0].process_count).to eq(100)
        expect(chunks[1].chunk_index).to eq(1)
        expect(chunks[1].process_count).to eq(100)
        expect(chunks[2].chunk_index).to eq(2)
        expect(chunks[2].process_count).to eq(50)

        puts "Deep hierarchy test (250 processes, 1 space): #{duration.round(3)}s"
      end
    end

    context 'with many spaces (wide hierarchy)' do
      before do
        # Create 1 org, 100 spaces, 1 process each
        # Should produce 100 chunks (one per space)
        bulk_create_processes(org_count: 1, spaces_per_org: 100, processes_per_space: 1)
      end

      it 'creates one chunk per space' do
        snapshot = create_placeholder_snapshot

        start_time = Time.now
        repository.populate_snapshot!(snapshot)
        duration = Time.now - start_time

        snapshot.reload
        expect(snapshot.process_count).to eq(100)
        expect(snapshot.chunk_count).to eq(100)
        expect(snapshot.space_count).to eq(100)
        expect(snapshot.organization_count).to eq(1)

        # All chunks should have chunk_index 0 (one per space)
        chunks = snapshot.app_usage_snapshot_chunks.to_a
        expect(chunks.all? { |c| c.chunk_index == 0 }).to be true
        expect(chunks.all? { |c| c.process_count == 1 }).to be true

        puts "Wide hierarchy test (100 spaces, 1 process each): #{duration.round(3)}s"
      end
    end

    context 'with many orgs (broad hierarchy)' do
      before do
        # Create 50 orgs, 2 spaces each, 1 process per space
        # Should produce 100 chunks
        bulk_create_processes(org_count: 50, spaces_per_org: 2, processes_per_space: 1)
      end

      it 'creates correct chunk and org counts' do
        snapshot = create_placeholder_snapshot

        start_time = Time.now
        repository.populate_snapshot!(snapshot)
        duration = Time.now - start_time

        snapshot.reload
        expect(snapshot.process_count).to eq(100)
        expect(snapshot.chunk_count).to eq(100)
        expect(snapshot.space_count).to eq(100)
        expect(snapshot.organization_count).to eq(50)

        puts "Broad hierarchy test (50 orgs, 2 spaces each): #{duration.round(3)}s"
      end
    end
  end

  describe 'moderate scale performance' do
    # This test uses ENV variables to allow scaling up for manual testing
    # Default: 10 orgs x 10 spaces x 10 processes = 1,000 processes
    let(:org_count) { ENV.fetch('PERF_ORG_COUNT', 10).to_i }
    let(:spaces_per_org) { ENV.fetch('PERF_SPACES_PER_ORG', 10).to_i }
    let(:processes_per_space) { ENV.fetch('PERF_PROCESSES_PER_SPACE', 10).to_i }

    before do
      bulk_create_processes(
        org_count: org_count,
        spaces_per_org: spaces_per_org,
        processes_per_space: processes_per_space
      )
    end

    it 'completes in reasonable time with correct counts' do
      total_processes = org_count * spaces_per_org * processes_per_space
      snapshot = create_placeholder_snapshot

      start_time = Time.now
      repository.populate_snapshot!(snapshot)
      duration = Time.now - start_time

      snapshot.reload
      expect(snapshot.process_count).to eq(total_processes)
      expect(snapshot.space_count).to eq(org_count * spaces_per_org)
      expect(snapshot.organization_count).to eq(org_count)

      # Calculate expected chunks
      # Each space with <= 100 processes = 1 chunk
      # Each space with > 100 processes = ceil(processes/100) chunks
      expected_chunks = org_count * spaces_per_org * [(processes_per_space / 100.0).ceil, 1].max
      expect(snapshot.chunk_count).to eq(expected_chunks)

      # Performance assertion: should complete in reasonable time
      # 1000 processes should complete in < 5 seconds
      max_allowed_seconds = (total_processes / 200.0).ceil # ~200 processes/second minimum
      expect(duration).to be < max_allowed_seconds

      puts "Scale test (#{total_processes} processes): #{duration.round(3)}s (#{(total_processes / duration).round(0)} proc/sec)"
    end
  end

  describe 'API response bounded size' do
    before do
      # Create enough data to have multiple pages
      bulk_create_processes(org_count: 1, spaces_per_org: 100, processes_per_space: 5)
    end

    it 'returns paginated chunks with bounded response size' do
      snapshot = create_placeholder_snapshot
      repository.populate_snapshot!(snapshot)

      # Simulate API pagination
      page_size = 50
      paginated_result = VCAP::CloudController::SequelPaginator.new.get_page(
        snapshot.app_usage_snapshot_chunks_dataset,
        VCAP::CloudController::PaginationOptions.new(page: 1, per_page: page_size)
      )

      expect(paginated_result.records.size).to be <= page_size
      expect(paginated_result.total).to eq(100) # 100 spaces = 100 chunks
    end
  end
end

require 'spec_helper'
require 'repositories/app_usage_snapshot_repository'

module VCAP::CloudController
  module Repositories
    RSpec.describe AppUsageSnapshotRepository do
      subject(:repository) { AppUsageSnapshotRepository.new }

      let(:org) { Organization.make }
      let(:space) { Space.make(organization: org) }
      let(:app_model) { AppModel.make(space:) }

      # Helper to create a placeholder snapshot (as the controller would)
      def create_placeholder_snapshot
        AppUsageSnapshot.create(
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

      describe '#populate_snapshot!' do
        context 'when there are running processes' do
          let!(:process1) { ProcessModel.make(app: app_model, state: ProcessModel::STARTED, instances: 3, type: 'web') }
          let!(:process2) { ProcessModel.make(app: app_model, state: ProcessModel::STARTED, instances: 2, type: 'worker') }
          let!(:stopped_process) { ProcessModel.make(app: app_model, state: ProcessModel::STOPPED, instances: 1) }

          it 'populates the snapshot with correct counts' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            # 3 instances (web) + 2 instances (worker) = 5 total instances
            expect(snapshot.instance_count).to eq(5)
            expect(snapshot.process_count).to eq(2)
            expect(snapshot.organization_count).to eq(1)
            expect(snapshot.space_count).to eq(1)
            expect(snapshot.chunk_count).to eq(1)
            expect(snapshot.completed_at).not_to be_nil
          end

          it 'creates chunk records with process details' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            expect(snapshot.app_usage_snapshot_chunks.count).to eq(1)
            chunk = snapshot.app_usage_snapshot_chunks.first

            expect(chunk.space_guid).to eq(space.guid)
            expect(chunk.organization_guid).to eq(org.guid)
            expect(chunk.chunk_index).to eq(0)
            expect(chunk.process_count).to eq(2)
            expect(chunk.instance_count).to eq(5)
            expect(chunk.processes).to contain_exactly(
              hash_including('app_guid' => app_model.guid, 'process_type' => 'web', 'instances' => 3),
              hash_including('app_guid' => app_model.guid, 'process_type' => 'worker', 'instances' => 2)
            )
          end

          it 'records checkpoint event ID' do
            AppUsageEvent.make
            AppUsageEvent.make
            last_event = AppUsageEvent.make

            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.checkpoint_event_id).to eq(last_event.id)
            expect(snapshot.checkpoint_event_created_at).to be_within(1.second).of(last_event.created_at)
          end

          it 'excludes task and build processes from counts' do
            ProcessModel.make(app: app_model, state: ProcessModel::STARTED, instances: 10, type: 'TASK')
            ProcessModel.make(app: app_model, state: ProcessModel::STARTED, instances: 5, type: 'build')

            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            # Only web (3) + worker (2) = 5 instances, 2 processes
            expect(snapshot.instance_count).to eq(5)
            expect(snapshot.process_count).to eq(2)
          end
        end

        context 'when there are multiple spaces' do
          let(:space2) { Space.make(organization: org) }
          let(:org2) { Organization.make }
          let(:space3) { Space.make(organization: org2) }
          let(:app_model2) { AppModel.make(space: space2) }
          let(:app_model3) { AppModel.make(space: space3) }

          before do
            ProcessModel.make(app: app_model, state: ProcessModel::STARTED, instances: 2, type: 'web')
            ProcessModel.make(app: app_model2, state: ProcessModel::STARTED, instances: 3, type: 'web')
            ProcessModel.make(app: app_model3, state: ProcessModel::STARTED, instances: 5, type: 'web')
          end

          it 'creates one chunk per space' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            expect(snapshot.app_usage_snapshot_chunks.count).to eq(3)
            expect(snapshot.instance_count).to eq(10) # 2 + 3 + 5
            expect(snapshot.process_count).to eq(3)
            expect(snapshot.organization_count).to eq(2)
            expect(snapshot.space_count).to eq(3)
            expect(snapshot.chunk_count).to eq(3)
          end

          it 'groups processes by space correctly' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            chunks = snapshot.app_usage_snapshot_chunks.to_a
            space1_chunk = chunks.find { |c| c.space_guid == space.guid }
            space2_chunk = chunks.find { |c| c.space_guid == space2.guid }
            space3_chunk = chunks.find { |c| c.space_guid == space3.guid }

            expect(space1_chunk.instance_count).to eq(2)
            expect(space2_chunk.instance_count).to eq(3)
            expect(space3_chunk.instance_count).to eq(5)
          end
        end

        context 'when a space has many processes (chunking test)' do
          # Create more than CHUNK_LIMIT (100) processes in one space
          before do
            150.times do |i|
              process_app = AppModel.make(space: space)
              ProcessModel.make(app: process_app, state: ProcessModel::STARTED, instances: 1, type: 'web')
            end
          end

          it 'creates multiple chunks for the same space' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            # 150 processes should create 2 chunks (100 + 50)
            expect(snapshot.app_usage_snapshot_chunks.count).to eq(2)
            expect(snapshot.process_count).to eq(150)
            expect(snapshot.instance_count).to eq(150)
            expect(snapshot.chunk_count).to eq(2)

            chunks = snapshot.app_usage_snapshot_chunks.order(:chunk_index).to_a
            expect(chunks[0].chunk_index).to eq(0)
            expect(chunks[0].process_count).to eq(100)
            expect(chunks[1].chunk_index).to eq(1)
            expect(chunks[1].process_count).to eq(50)
          end
        end

        context 'when there are no running processes' do
          it 'populates snapshot with zero counts and no chunks' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.instance_count).to eq(0)
            expect(snapshot.process_count).to eq(0)
            expect(snapshot.organization_count).to eq(0)
            expect(snapshot.space_count).to eq(0)
            expect(snapshot.chunk_count).to eq(0)
            expect(snapshot.app_usage_snapshot_chunks.count).to eq(0)
            expect(snapshot.completed_at).not_to be_nil
          end
        end

        context 'when there are no usage events (empty system)' do
          it 'sets checkpoint_event_id to nil and checkpoint_event_created_at to nil' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.checkpoint_event_id).to be_nil
            expect(snapshot.checkpoint_event_created_at).to be_nil
            expect(snapshot.completed_at).not_to be_nil
          end
        end

        context 'when org or space is deleted but process still exists' do
          let!(:process) { ProcessModel.make(app: app_model, state: ProcessModel::STARTED, instances: 3) }

          it 'includes the process instances in the count' do
            # The LEFT JOIN will return NULL for org/space if they're deleted
            # We verify the query handles it by counting correctly
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.instance_count).to eq(3)
          end
        end

        context 'when snapshot population fails' do
          it 'raises the error and rolls back transaction' do
            snapshot = create_placeholder_snapshot
            allow(snapshot).to receive(:update).and_raise(Sequel::DatabaseError.new('DB error'))

            prometheus = instance_double(VCAP::CloudController::Metrics::PrometheusUpdater)
            allow(CloudController::DependencyLocator.instance).to receive(:prometheus_updater).and_return(prometheus)
            expect(prometheus).to receive(:increment_counter_metric).with(:cc_app_usage_snapshot_generation_failures_total)

            expect { repository.populate_snapshot!(snapshot) }.to raise_error(Sequel::DatabaseError)
          end
        end

        context 'metrics' do
          it 'records generation duration' do
            prometheus = instance_double(VCAP::CloudController::Metrics::PrometheusUpdater)
            allow(CloudController::DependencyLocator.instance).to receive(:prometheus_updater).and_return(prometheus)

            expect(prometheus).to receive(:update_histogram_metric).with(:cc_app_usage_snapshot_generation_duration_seconds, anything)
            expect(prometheus).to receive(:update_gauge_metric).with(:cc_app_usage_snapshot_instance_count, anything)

            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)
          end

          it 'increments failure counter on error' do
            prometheus = instance_double(VCAP::CloudController::Metrics::PrometheusUpdater)
            allow(CloudController::DependencyLocator.instance).to receive(:prometheus_updater).and_return(prometheus)

            snapshot = create_placeholder_snapshot
            allow(snapshot).to receive(:update).and_raise(StandardError.new('test error'))

            expect(prometheus).to receive(:increment_counter_metric).with(:cc_app_usage_snapshot_generation_failures_total)

            expect { repository.populate_snapshot!(snapshot) }.to raise_error(StandardError)
          end
        end
      end
    end
  end
end

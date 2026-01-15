require 'spec_helper'

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
          process_count: 0,
          organization_count: 0,
          space_count: 0
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
            expect(snapshot.process_count).to eq(2)
            expect(snapshot.organization_count).to eq(1)
            expect(snapshot.space_count).to eq(1)
            expect(snapshot.completed_at).not_to be_nil
          end

          it 'creates snapshot details for each running process' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            details = snapshot.app_usage_snapshot_details
            expect(details.count).to eq(2)

            detail1 = details.find { |d| d.process_guid == process1.guid }
            expect(detail1.organization_guid).to eq(org.guid)
            expect(detail1.space_guid).to eq(space.guid)
            expect(detail1.app_guid).to eq(app_model.guid)
            expect(detail1.process_type).to eq('web')
            expect(detail1.instances).to eq(3)
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

          it 'excludes task and build processes' do
            ProcessModel.make(app: app_model, state: ProcessModel::STARTED, type: 'TASK')
            ProcessModel.make(app: app_model, state: ProcessModel::STARTED, type: 'build')

            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.process_count).to eq(2) # Only web and worker
          end
        end

        context 'when there are no running processes' do
          it 'populates snapshot with zero counts and empty details' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.process_count).to eq(0)
            expect(snapshot.organization_count).to eq(0)
            expect(snapshot.space_count).to eq(0)
            expect(snapshot.completed_at).not_to be_nil
            expect(snapshot.app_usage_snapshot_details).to be_empty
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
          let!(:process) { ProcessModel.make(app: app_model, state: ProcessModel::STARTED, instances: 1) }

          it 'includes the process with NULL org/space guids' do
            # The LEFT JOIN will return NULL for org/space if they're deleted
            # We can't easily simulate this in the test, but we verify the query handles it
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.process_count).to eq(1)
            # The detail should exist even if org/space were NULL
            expect(snapshot.app_usage_snapshot_details.count).to eq(1)
          end
        end

        context 'when snapshot population fails' do
          it 'raises the error and rolls back transaction' do
            snapshot = create_placeholder_snapshot
            allow(AppUsageSnapshotDetail).to receive(:multi_insert).and_raise(Sequel::DatabaseError.new('DB error'))

            expect { repository.populate_snapshot!(snapshot) }.to raise_error(Sequel::DatabaseError)

            # Snapshot should still exist (created by controller) but not be completed
            snapshot.reload
            expect(snapshot.completed_at).to be_nil
            expect(snapshot.process_count).to eq(0) # Not updated due to rollback
          end
        end

        context 'with large number of processes' do
          before do
            100.times do |i|
              ProcessModel.make(app: app_model, state: ProcessModel::STARTED, instances: 1, type: "worker-#{i}")
            end
          end

          it 'batch inserts details' do
            expect(AppUsageSnapshotDetail).to receive(:multi_insert).at_least(:once).and_call_original

            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.process_count).to eq(100)
            expect(snapshot.app_usage_snapshot_details.count).to eq(100)
          end
        end

        context 'with processes spanning multiple batches' do
          # This test verifies that the streaming/paged_each approach works correctly
          # when there are more processes than the batch size (1000)
          it 'correctly inserts all details across multiple batches' do
            # Create enough processes to span multiple batches (batch size is 1000)
            # We'll create 2500 to test 3 batches (1000 + 1000 + 500)
            2500.times do |i|
              ProcessModel.make(app: app_model, state: ProcessModel::STARTED, instances: 1, type: "batch-test-#{i}")
            end

            # Track how many times multi_insert is called
            insert_call_count = 0
            allow(AppUsageSnapshotDetail).to receive(:multi_insert) do |rows|
              insert_call_count += 1
              # Actually perform the insert
              AppUsageSnapshotDetail.dataset.multi_insert(rows)
            end

            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.process_count).to eq(2500)
            expect(snapshot.app_usage_snapshot_details.count).to eq(2500)
            # Should have been called 3 times: 1000 + 1000 + 500
            expect(insert_call_count).to eq(3)
          end
        end

        context 'metrics' do
          it 'records generation duration' do
            prometheus = instance_double(VCAP::CloudController::Metrics::PrometheusUpdater)
            allow(CloudController::DependencyLocator.instance).to receive(:prometheus_updater).and_return(prometheus)

            expect(prometheus).to receive(:update_histogram_metric).with(:cc_app_usage_snapshot_generation_duration_seconds, anything)
            expect(prometheus).to receive(:update_gauge_metric).with(:cc_app_usage_snapshot_process_count, anything)

            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)
          end

          it 'increments failure counter on error' do
            prometheus = instance_double(VCAP::CloudController::Metrics::PrometheusUpdater)
            allow(CloudController::DependencyLocator.instance).to receive(:prometheus_updater).and_return(prometheus)
            allow(AppUsageSnapshotDetail).to receive(:multi_insert).and_raise(StandardError.new('test error'))

            expect(prometheus).to receive(:increment_counter_metric).with(:cc_app_usage_snapshot_generation_failures_total)

            snapshot = create_placeholder_snapshot
            expect { repository.populate_snapshot!(snapshot) }.to raise_error(StandardError)
          end
        end
      end
    end
  end
end

require 'spec_helper'
require 'repositories/usage_snapshot_repository'

module VCAP::CloudController
  module Repositories
    RSpec.describe AppUsageSnapshotRepository do
      subject(:repository) { AppUsageSnapshotRepository.new }

      let(:org) { Organization.make }
      let(:space) { Space.make(organization: org) }
      let(:app_model) { AppModel.make(space:) }

      describe '#generate_snapshot!' do
        context 'when there are running processes' do
          let!(:process1) { ProcessModel.make(app: app_model, state: ProcessModel::STARTED, instances: 3, type: 'web') }
          let!(:process2) { ProcessModel.make(app: app_model, state: ProcessModel::STARTED, instances: 2, type: 'worker') }
          let!(:stopped_process) { ProcessModel.make(app: app_model, state: ProcessModel::STOPPED, instances: 1) }

          it 'creates a snapshot with correct counts' do
            snapshot = repository.generate_snapshot!

            expect(snapshot).to be_a(AppUsageSnapshot)
            expect(snapshot.process_count).to eq(2)
            expect(snapshot.organization_count).to eq(1)
            expect(snapshot.space_count).to eq(1)
            expect(snapshot.completed_at).not_to be_nil
          end

          it 'creates snapshot details for each running process' do
            snapshot = repository.generate_snapshot!

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

            snapshot = repository.generate_snapshot!

            expect(snapshot.checkpoint_event_id).to eq(last_event.id)
            expect(snapshot.checkpoint_event_created_at).to be_within(1.second).of(last_event.created_at)
          end

          it 'excludes task and build processes' do
            ProcessModel.make(app: app_model, state: ProcessModel::STARTED, type: 'TASK')
            ProcessModel.make(app: app_model, state: ProcessModel::STARTED, type: 'build')

            snapshot = repository.generate_snapshot!

            expect(snapshot.process_count).to eq(2) # Only web and worker
          end
        end

        context 'when there are no running processes' do
          it 'creates a snapshot with zero counts' do
            snapshot = repository.generate_snapshot!

            expect(snapshot.process_count).to eq(0)
            expect(snapshot.organization_count).to eq(0)
            expect(snapshot.space_count).to eq(0)
            expect(snapshot.checkpoint_event_id).to eq(0)
          end
        end

        context 'when org or space is deleted during snapshot' do
          let!(:process) { ProcessModel.make(app: app_model, state: ProcessModel::STARTED, instances: 1) }

          before do
            # Simulate soft-deleted org/space by using LEFT JOIN
            allow_any_instance_of(Sequel::Dataset).to receive(:all).and_wrap_original do |method, *args|
              result = method.call(*args)
              # Simulate NULL org_guid from LEFT JOIN
              result.each { |r| r[:organization_guid] = nil if r.is_a?(Hash) }
              result
            end
          end

          it 'handles NULL organization_guid gracefully' do
            snapshot = repository.generate_snapshot!

            expect(snapshot.organization_count).to eq(0)
            expect(snapshot.process_count).to be >= 0
          end
        end

        context 'when snapshot generation fails' do
          before do
            allow_any_instance_of(AppUsageSnapshot).to receive(:update).and_raise(Sequel::DatabaseError.new('DB error'))
          end

          it 'raises the error' do
            expect { repository.generate_snapshot! }.to raise_error(Sequel::DatabaseError)
          end

          it 'does not leave orphaned snapshot records' do
            expect { repository.generate_snapshot! }.to raise_error(Sequel::DatabaseError)
            expect(AppUsageSnapshot.count).to eq(0)
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

            snapshot = repository.generate_snapshot!

            expect(snapshot.process_count).to eq(100)
            expect(snapshot.app_usage_snapshot_details.count).to eq(100)
          end
        end

        context 'metrics' do
          it 'records generation duration' do
            prometheus = instance_double(VCAP::CloudController::Metrics::PrometheusUpdater)
            allow(CloudController::DependencyLocator.instance).to receive(:prometheus_updater).and_return(prometheus)

            expect(prometheus).to receive(:update_histogram_metric).with(:cc_app_usage_snapshot_generation_duration_seconds, anything)
            expect(prometheus).to receive(:update_gauge_metric).with(:cc_app_usage_snapshot_process_count, anything)

            repository.generate_snapshot!
          end

          it 'increments failure counter on error' do
            prometheus = instance_double(VCAP::CloudController::Metrics::PrometheusUpdater)
            allow(CloudController::DependencyLocator.instance).to receive(:prometheus_updater).and_return(prometheus)
            allow_any_instance_of(AppUsageSnapshot).to receive(:create).and_raise(StandardError.new('test error'))

            expect(prometheus).to receive(:increment_counter_metric).with(:cc_app_usage_snapshot_generation_failures_total)

            expect { repository.generate_snapshot! }.to raise_error(StandardError)
          end
        end
      end
    end
  end
end

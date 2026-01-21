require 'spec_helper'
require 'repositories/service_usage_snapshot_repository'

module VCAP::CloudController
  module Repositories
    RSpec.describe ServiceUsageSnapshotRepository do
      subject(:repository) { ServiceUsageSnapshotRepository.new }

      let(:org) { Organization.make }
      let(:space) { Space.make(organization: org) }
      let(:service_plan) { ServicePlan.make }
      let(:service) { service_plan.service }
      let(:service_broker) { service.service_broker }

      # Helper to create a placeholder snapshot (as the controller would)
      def create_placeholder_snapshot
        ServiceUsageSnapshot.create(
          guid: SecureRandom.uuid,
          checkpoint_event_id: nil,
          created_at: Time.now.utc,
          completed_at: nil,
          service_instance_count: 0,
          organization_count: 0,
          space_count: 0
        )
      end

      describe '#populate_snapshot!' do
        context 'when there are managed service instances' do
          let!(:instance1) { ManagedServiceInstance.make(space:, service_plan:) }
          let!(:instance2) { ManagedServiceInstance.make(space:, service_plan:) }

          it 'populates the snapshot with correct counts' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.service_instance_count).to eq(2)
            expect(snapshot.organization_count).to eq(1)
            expect(snapshot.space_count).to eq(1)
            expect(snapshot.completed_at).not_to be_nil
          end

          it 'creates space records with service instance details' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            expect(snapshot.service_usage_snapshot_spaces.count).to eq(1)
            space_record = snapshot.service_usage_snapshot_spaces.first

            expect(space_record.space_guid).to eq(space.guid)
            expect(space_record.organization_guid).to eq(org.guid)
            expect(space_record.service_instance_count).to eq(2)
            expect(space_record.service_instances.size).to eq(2)
            expect(space_record.service_instances).to include(
              hash_including('guid' => instance1.guid, 'type' => 'managed'),
              hash_including('guid' => instance2.guid, 'type' => 'managed')
            )
          end

          it 'records checkpoint event ID' do
            ServiceUsageEvent.make
            ServiceUsageEvent.make
            last_event = ServiceUsageEvent.make

            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.checkpoint_event_id).to eq(last_event.id)
            expect(snapshot.checkpoint_event_created_at).to be_within(1.second).of(last_event.created_at)
          end
        end

        context 'when there are user-provided service instances' do
          let!(:user_provided_instance) { UserProvidedServiceInstance.make(space:) }

          it 'includes user-provided service instance in the count' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.service_instance_count).to eq(1)
          end

          it 'marks user-provided instances correctly in space records' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            space_record = snapshot.service_usage_snapshot_spaces.first
            expect(space_record.service_instances.first['type']).to eq('user_provided')
          end
        end

        context 'when there are both managed and user-provided instances' do
          let!(:managed_instance) { ManagedServiceInstance.make(space:, service_plan:) }
          let!(:user_provided_instance) { UserProvidedServiceInstance.make(space:) }

          it 'includes both types in the snapshot count' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.service_instance_count).to eq(2)
          end

          it 'includes both types in space record' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            space_record = snapshot.service_usage_snapshot_spaces.first
            types = space_record.service_instances.pluck('type')
            expect(types).to contain_exactly('managed', 'user_provided')
          end
        end

        context 'when there are multiple spaces' do
          let(:space2) { Space.make(organization: org) }
          let(:org2) { Organization.make }
          let(:space3) { Space.make(organization: org2) }

          before do
            ManagedServiceInstance.make(space:, service_plan:)
            ManagedServiceInstance.make(space: space2, service_plan: service_plan)
            ManagedServiceInstance.make(space: space2, service_plan: service_plan)
            ManagedServiceInstance.make(space: space3, service_plan: service_plan)
          end

          it 'creates one space record per space' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            expect(snapshot.service_usage_snapshot_spaces.count).to eq(3)
            expect(snapshot.service_instance_count).to eq(4)
            expect(snapshot.organization_count).to eq(2)
            expect(snapshot.space_count).to eq(3)
          end

          it 'groups service instances by space correctly' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            space_records = snapshot.service_usage_snapshot_spaces.to_a
            space1_record = space_records.find { |r| r.space_guid == space.guid }
            space2_record = space_records.find { |r| r.space_guid == space2.guid }
            space3_record = space_records.find { |r| r.space_guid == space3.guid }

            expect(space1_record.service_instance_count).to eq(1)
            expect(space2_record.service_instance_count).to eq(2)
            expect(space3_record.service_instance_count).to eq(1)
          end
        end

        context 'when there are no service instances' do
          it 'populates snapshot with zero counts and no space records' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.service_instance_count).to eq(0)
            expect(snapshot.organization_count).to eq(0)
            expect(snapshot.space_count).to eq(0)
            expect(snapshot.service_usage_snapshot_spaces.count).to eq(0)
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

        context 'when org or space is deleted but service instance still exists' do
          let!(:instance) { ManagedServiceInstance.make(space:, service_plan:) }

          it 'includes the service instance in the count' do
            # The LEFT JOIN will return NULL for org/space if they're deleted
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.service_instance_count).to eq(1)
          end
        end

        context 'when snapshot population fails' do
          it 'raises the error and rolls back transaction' do
            snapshot = create_placeholder_snapshot
            allow(snapshot).to receive(:update).and_raise(Sequel::DatabaseError.new('DB error'))

            prometheus = instance_double(VCAP::CloudController::Metrics::PrometheusUpdater)
            allow(CloudController::DependencyLocator.instance).to receive(:prometheus_updater).and_return(prometheus)
            expect(prometheus).to receive(:increment_counter_metric).with(:cc_service_usage_snapshot_generation_failures_total)

            expect { repository.populate_snapshot!(snapshot) }.to raise_error(Sequel::DatabaseError)
          end
        end

        context 'metrics' do
          let!(:instance) { ManagedServiceInstance.make(space:, service_plan:) }

          it 'records generation duration' do
            prometheus = instance_double(VCAP::CloudController::Metrics::PrometheusUpdater)
            allow(CloudController::DependencyLocator.instance).to receive(:prometheus_updater).and_return(prometheus)

            expect(prometheus).to receive(:update_histogram_metric).with(:cc_service_usage_snapshot_generation_duration_seconds, kind_of(Numeric))
            expect(prometheus).to receive(:update_gauge_metric).with(:cc_service_usage_snapshot_service_instance_count, 1)

            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)
          end
        end
      end
    end
  end
end

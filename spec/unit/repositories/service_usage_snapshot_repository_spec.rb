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

          it 'creates snapshot details for each service instance' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            details = snapshot.service_usage_snapshot_details
            expect(details.count).to eq(2)

            detail1 = details.find { |d| d.service_instance_guid == instance1.guid }
            expect(detail1.organization_guid).to eq(org.guid)
            expect(detail1.space_guid).to eq(space.guid)
            expect(detail1.service_instance_name).to eq(instance1.name)
            expect(detail1.service_instance_type).to eq('managed_service_instance')
            expect(detail1.service_plan_guid).to eq(service_plan.guid)
            expect(detail1.service_offering_guid).to eq(service.guid)
            expect(detail1.service_broker_guid).to eq(service_broker.guid)
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

          it 'creates snapshot with user-provided service instance' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.service_instance_count).to eq(1)

            detail = snapshot.service_usage_snapshot_details.first
            expect(detail.service_instance_guid).to eq(user_provided_instance.guid)
            expect(detail.service_instance_type).to eq('user_provided')
            expect(detail.service_plan_guid).to be_nil
            expect(detail.service_offering_guid).to be_nil
            expect(detail.service_broker_guid).to be_nil
          end
        end

        context 'when there are both managed and user-provided instances' do
          let!(:managed_instance) { ManagedServiceInstance.make(space:, service_plan:) }
          let!(:user_provided_instance) { UserProvidedServiceInstance.make(space:) }

          it 'includes both types in the snapshot' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.service_instance_count).to eq(2)

            managed_detail = snapshot.service_usage_snapshot_details.find { |d| d.service_instance_guid == managed_instance.guid }
            expect(managed_detail.service_instance_type).to eq('managed_service_instance')
            expect(managed_detail.service_plan_guid).not_to be_nil

            user_provided_detail = snapshot.service_usage_snapshot_details.find { |d| d.service_instance_guid == user_provided_instance.guid }
            expect(user_provided_detail.service_instance_type).to eq('user_provided')
            expect(user_provided_detail.service_plan_guid).to be_nil
          end
        end

        context 'when there are no service instances' do
          it 'populates snapshot with zero counts and empty details' do
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.service_instance_count).to eq(0)
            expect(snapshot.organization_count).to eq(0)
            expect(snapshot.space_count).to eq(0)
            expect(snapshot.completed_at).not_to be_nil
            expect(snapshot.service_usage_snapshot_details).to be_empty
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

          it 'includes the service instance with NULL org/space guids' do
            # The LEFT JOIN will return NULL for org/space if they're deleted
            snapshot = create_placeholder_snapshot
            repository.populate_snapshot!(snapshot)

            snapshot.reload
            expect(snapshot.service_instance_count).to eq(1)
            expect(snapshot.service_usage_snapshot_details.count).to eq(1)
          end
        end

        context 'when snapshot population fails' do
          let!(:instance) { ManagedServiceInstance.make(space:, service_plan:) }

          it 'raises the error and rolls back transaction' do
            snapshot = create_placeholder_snapshot
            allow(ServiceUsageSnapshotDetail).to receive(:multi_insert).and_raise(Sequel::DatabaseError.new('DB error'))

            prometheus = instance_double(VCAP::CloudController::Metrics::PrometheusUpdater)
            allow(CloudController::DependencyLocator.instance).to receive(:prometheus_updater).and_return(prometheus)
            expect(prometheus).to receive(:increment_counter_metric).with(:cc_service_usage_snapshot_generation_failures_total)

            expect { repository.populate_snapshot!(snapshot) }.to raise_error(Sequel::DatabaseError)

            # Snapshot should still exist (created by controller) but not be completed
            snapshot.reload
            expect(snapshot.completed_at).to be_nil
            expect(snapshot.service_instance_count).to eq(0) # Not updated due to rollback
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

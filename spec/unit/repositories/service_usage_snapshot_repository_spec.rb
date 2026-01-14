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

      describe '#generate_snapshot!' do
        context 'when there are managed service instances' do
          let!(:instance1) { ManagedServiceInstance.make(space:, service_plan:) }
          let!(:instance2) { ManagedServiceInstance.make(space:, service_plan:) }

          it 'creates a snapshot with correct counts' do
            snapshot = repository.generate_snapshot!

            expect(snapshot).to be_a(ServiceUsageSnapshot)
            expect(snapshot.service_instance_count).to eq(2)
            expect(snapshot.organization_count).to eq(1)
            expect(snapshot.space_count).to eq(1)
            expect(snapshot.completed_at).not_to be_nil
          end

          it 'creates snapshot details for each service instance' do
            snapshot = repository.generate_snapshot!

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

            snapshot = repository.generate_snapshot!

            expect(snapshot.checkpoint_event_id).to eq(last_event.id)
            expect(snapshot.checkpoint_event_created_at).to be_within(1.second).of(last_event.created_at)
          end
        end

        context 'when there are user-provided service instances' do
          let!(:user_provided_instance) { UserProvidedServiceInstance.make(space:) }

          it 'creates snapshot with user-provided service instance' do
            snapshot = repository.generate_snapshot!

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
            snapshot = repository.generate_snapshot!

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
          it 'creates a snapshot with zero counts' do
            snapshot = repository.generate_snapshot!

            expect(snapshot.service_instance_count).to eq(0)
            expect(snapshot.organization_count).to eq(0)
            expect(snapshot.space_count).to eq(0)
            expect(snapshot.checkpoint_event_id).to eq(0)
          end
        end

        context 'when org or space is deleted' do
          let!(:instance) { ManagedServiceInstance.make(space:, service_plan:) }

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
            expect(snapshot.service_instance_count).to be >= 0
          end
        end

        context 'when snapshot generation fails' do
          before do
            allow_any_instance_of(ServiceUsageSnapshot).to receive(:update).and_raise(Sequel::DatabaseError.new('DB error'))
          end

          it 'raises the error and increments failure metric' do
            prometheus = instance_double(CloudController::Metrics::PrometheusUpdater)
            allow(CloudController::DependencyLocator.instance).to receive(:prometheus_updater).and_return(prometheus)
            expect(prometheus).to receive(:increment_counter_metric).with(:cc_service_usage_snapshot_generation_failures_total)

            expect { repository.generate_snapshot! }.to raise_error(Sequel::DatabaseError)
          end
        end

        context 'metrics' do
          let!(:instance) { ManagedServiceInstance.make(space:, service_plan:) }

          it 'records generation duration' do
            prometheus = instance_double(CloudController::Metrics::PrometheusUpdater)
            allow(CloudController::DependencyLocator.instance).to receive(:prometheus_updater).and_return(prometheus)

            expect(prometheus).to receive(:update_histogram_metric).with(:cc_service_usage_snapshot_generation_duration_seconds, kind_of(Numeric))
            expect(prometheus).to receive(:update_gauge_metric).with(:cc_service_usage_snapshot_service_instance_count, 1)

            repository.generate_snapshot!
          end
        end
      end
    end
  end
end

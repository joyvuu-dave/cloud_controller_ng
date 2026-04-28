require 'spec_helper'
require 'migrations/helpers/migration_shared_context'

RSpec.describe 'migration to seed WAS_RUNNING events for existing service instances', isolation: :truncation, type: :migration do
  include_context 'migration' do
    let(:migration_filename) { '20260428120001_seed_was_running_service_usage_events.rb' }
  end

  let(:run_migration) do
    Sequel::Migrator.run(db, migrations_path, target: current_migration_index, allow_missing_migration_files: true)
  end

  let(:revert_migration) do
    Sequel::Migrator.run(db, migrations_path, target: current_migration_index - 1, allow_missing_migration_files: true)
  end

  describe 'up migration' do
    context 'when there are no service instances' do
      it 'inserts no rows' do
        expect { run_migration }.not_to change { db[:service_usage_events].where(state: 'WAS_RUNNING').count }.from(0)
      end
    end

    context 'when there is one managed service instance' do
      let!(:instance) { VCAP::CloudController::ManagedServiceInstance.make(name: 'my-instance') }

      it 'inserts one WAS_RUNNING row with managed_service_instance type and full broker chain' do
        expect { run_migration }.to change { db[:service_usage_events].where(state: 'WAS_RUNNING').count }.from(0).to(1)

        row = db[:service_usage_events].where(state: 'WAS_RUNNING').first
        expect(row[:guid]).to be_present
        expect(row[:state]).to eq('WAS_RUNNING')
        expect(row[:service_instance_guid]).to eq(instance.guid)
        expect(row[:service_instance_name]).to eq('my-instance')
        expect(row[:service_instance_type]).to eq('managed_service_instance')
        expect(row[:service_plan_guid]).to eq(instance.service_plan.guid)
        expect(row[:service_plan_name]).to eq(instance.service_plan.name)
        expect(row[:service_guid]).to eq(instance.service_plan.service.guid)
        expect(row[:service_label]).to eq(instance.service_plan.service.label)
        expect(row[:service_broker_name]).to eq(instance.service_plan.service.service_broker.name)
        expect(row[:service_broker_guid]).to eq(instance.service_plan.service.service_broker.guid)
        expect(row[:space_guid]).to eq(instance.space.guid)
        expect(row[:space_name]).to eq(instance.space.name)
        expect(row[:org_guid]).to eq(instance.space.organization.guid)
      end
    end

    context 'when there is one user-provided service instance' do
      let!(:instance) { VCAP::CloudController::UserProvidedServiceInstance.make(name: 'upsi') }

      it 'inserts one WAS_RUNNING row with user_provided_service_instance type and NULL plan/service/broker fields' do
        expect { run_migration }.to change { db[:service_usage_events].where(state: 'WAS_RUNNING').count }.from(0).to(1)

        row = db[:service_usage_events].where(state: 'WAS_RUNNING').first
        expect(row[:service_instance_guid]).to eq(instance.guid)
        expect(row[:service_instance_name]).to eq('upsi')
        expect(row[:service_instance_type]).to eq('user_provided_service_instance')
        expect(row[:service_plan_guid]).to be_nil
        expect(row[:service_plan_name]).to be_nil
        expect(row[:service_guid]).to be_nil
        expect(row[:service_label]).to be_nil
        expect(row[:service_broker_name]).to be_nil
        expect(row[:service_broker_guid]).to be_nil
      end
    end

    context 'when there are managed and user-provided instances mixed' do
      let!(:managed) { VCAP::CloudController::ManagedServiceInstance.make }
      let!(:upsi) { VCAP::CloudController::UserProvidedServiceInstance.make }

      it 'inserts one WAS_RUNNING row per instance with the correct type' do
        run_migration

        rows = db[:service_usage_events].where(state: 'WAS_RUNNING').all
        expect(rows.size).to eq(2)

        managed_row = rows.find { |r| r[:service_instance_guid] == managed.guid }
        upsi_row = rows.find { |r| r[:service_instance_guid] == upsi.guid }

        expect(managed_row[:service_instance_type]).to eq('managed_service_instance')
        expect(managed_row[:service_plan_guid]).to be_present
        expect(upsi_row[:service_instance_type]).to eq('user_provided_service_instance')
        expect(upsi_row[:service_plan_guid]).to be_nil
      end
    end

    context 'when there are pre-existing rows in service_usage_events' do
      let!(:instance) { VCAP::CloudController::ManagedServiceInstance.make }
      let!(:existing_event) { VCAP::CloudController::ServiceUsageEvent.make(state: 'CREATED', service_instance_guid: instance.guid) }

      it 'preserves the existing rows (no truncate)' do
        expect { run_migration }.to change(VCAP::CloudController::ServiceUsageEvent, :count).by(1)
        expect(VCAP::CloudController::ServiceUsageEvent.where(guid: existing_event.guid).first).to be_present
      end
    end
  end

  describe 'down migration' do
    let!(:instance) { VCAP::CloudController::ManagedServiceInstance.make }
    let!(:unrelated_event) { VCAP::CloudController::ServiceUsageEvent.make(state: 'CREATED', service_instance_guid: instance.guid) }

    before { run_migration }

    it 'removes only the WAS_RUNNING rows' do
      expect(db[:service_usage_events].where(state: 'WAS_RUNNING').count).to eq(1)

      revert_migration

      expect(db[:service_usage_events].where(state: 'WAS_RUNNING').count).to eq(0)
      expect(db[:service_usage_events].where(guid: unrelated_event.guid).count).to eq(1)
    end
  end
end

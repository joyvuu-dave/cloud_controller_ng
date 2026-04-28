require 'spec_helper'
require 'migrations/helpers/migration_shared_context'

RSpec.describe 'migration to seed WAS_RUNNING events for currently-running app processes', isolation: :truncation, type: :migration do
  include_context 'migration' do
    let(:migration_filename) { '20260428120000_seed_was_running_app_usage_events.rb' }
  end

  let(:run_migration) do
    Sequel::Migrator.run(db, migrations_path, target: current_migration_index, allow_missing_migration_files: true)
  end

  let(:revert_migration) do
    Sequel::Migrator.run(db, migrations_path, target: current_migration_index - 1, allow_missing_migration_files: true)
  end

  describe 'up migration' do
    context 'when there are no processes' do
      it 'inserts no rows' do
        expect { run_migration }.not_to change { db[:app_usage_events].where(state: 'WAS_RUNNING').count }.from(0)
      end
    end

    context 'when there is one STARTED process' do
      let(:parent_app) { VCAP::CloudController::AppModel.make(name: 'my-app') }
      let!(:process) { VCAP::CloudController::ProcessModelFactory.make(app: parent_app, type: 'web', state: 'STARTED', instances: 3, memory: 512) }

      it 'inserts one WAS_RUNNING row with the expected fields' do
        expect { run_migration }.to change { db[:app_usage_events].where(state: 'WAS_RUNNING').count }.from(0).to(1)

        row = db[:app_usage_events].where(state: 'WAS_RUNNING').first
        expect(row[:guid]).to be_present
        expect(row[:state]).to eq('WAS_RUNNING')
        expect(row[:previous_state]).to be_nil
        expect(row[:app_guid]).to eq(process.guid)
        expect(row[:app_name]).to eq('my-app')
        expect(row[:parent_app_guid]).to eq(parent_app.guid)
        expect(row[:parent_app_name]).to eq('my-app')
        expect(row[:space_guid]).to eq(parent_app.space.guid)
        expect(row[:space_name]).to eq(parent_app.space.name)
        expect(row[:org_guid]).to eq(parent_app.space.organization.guid)
        expect(row[:instance_count]).to eq(3)
        expect(row[:previous_instance_count]).to eq(3)
        expect(row[:memory_in_mb_per_instance]).to eq(512)
        expect(row[:previous_memory_in_mb_per_instance]).to eq(512)
        expect(row[:previous_package_state]).to eq('UNKNOWN')
      end
    end

    context 'when there is a STOPPED process' do
      let(:parent_app) { VCAP::CloudController::AppModel.make }
      let!(:process) { VCAP::CloudController::ProcessModelFactory.make(app: parent_app, state: 'STOPPED') }

      it 'does not insert a row for the stopped process' do
        expect { run_migration }.not_to change { db[:app_usage_events].where(state: 'WAS_RUNNING').count }.from(0)
      end
    end

    context 'when there is a mix of STARTED and STOPPED processes' do
      let(:running_app) { VCAP::CloudController::AppModel.make }
      let(:stopped_app) { VCAP::CloudController::AppModel.make }
      let!(:running_process) { VCAP::CloudController::ProcessModelFactory.make(app: running_app, state: 'STARTED') }
      let!(:stopped_process) { VCAP::CloudController::ProcessModelFactory.make(app: stopped_app, state: 'STOPPED') }

      it 'inserts a WAS_RUNNING row only for the started process' do
        run_migration

        rows = db[:app_usage_events].where(state: 'WAS_RUNNING').all
        expect(rows.size).to eq(1)
        expect(rows.first[:app_guid]).to eq(running_process.guid)
      end
    end

    context 'when there are pre-existing rows in app_usage_events' do
      let(:parent_app) { VCAP::CloudController::AppModel.make }
      let!(:process) { VCAP::CloudController::ProcessModelFactory.make(app: parent_app, state: 'STARTED') }
      let!(:existing_event) { VCAP::CloudController::AppUsageEvent.make(state: 'STARTED', app_guid: parent_app.guid) }

      it 'preserves the existing rows (no truncate)' do
        expect { run_migration }.to change(VCAP::CloudController::AppUsageEvent, :count).by(1)
        expect(VCAP::CloudController::AppUsageEvent.where(guid: existing_event.guid).first).to be_present
      end
    end

    context 'when an app has a desired droplet in STAGED state' do
      let(:parent_app) { VCAP::CloudController::AppModel.make }
      let!(:process) { VCAP::CloudController::ProcessModelFactory.make(app: parent_app, state: 'STARTED') }

      it 'sets package_state to STAGED' do
        run_migration
        row = db[:app_usage_events].where(state: 'WAS_RUNNING').first
        expect(row[:package_state]).to eq('STAGED')
      end
    end

    context 'when multiple started processes exist' do
      let(:apps) { Array.new(3) { VCAP::CloudController::AppModel.make } }

      before do
        apps.each { |app| VCAP::CloudController::ProcessModelFactory.make(app: app, state: 'STARTED') }
      end

      it 'inserts one WAS_RUNNING row per running process' do
        expect { run_migration }.to change { db[:app_usage_events].where(state: 'WAS_RUNNING').count }.from(0).to(3)
      end
    end
  end

  describe 'down migration' do
    let(:parent_app) { VCAP::CloudController::AppModel.make }
    let!(:process) { VCAP::CloudController::ProcessModelFactory.make(app: parent_app, state: 'STARTED') }
    let!(:unrelated_event) { VCAP::CloudController::AppUsageEvent.make(state: 'STARTED', app_guid: parent_app.guid) }

    before { run_migration }

    it 'removes only the WAS_RUNNING rows' do
      expect(db[:app_usage_events].where(state: 'WAS_RUNNING').count).to eq(1)

      revert_migration

      expect(db[:app_usage_events].where(state: 'WAS_RUNNING').count).to eq(0)
      expect(db[:app_usage_events].where(guid: unrelated_event.guid).count).to eq(1)
    end
  end
end

require 'spec_helper'
require 'database/old_record_cleanup'

RSpec.describe Database::OldRecordCleanup do
  describe '#delete' do
    let(:threshold_for_keeping_unprocessed_records) { 5_000_000 }
    let(:cutoff_age_in_days) { 1 }

    before do
      allow(VCAP::CloudController::Config.config).to receive(:get).with(:app_usage_events).and_return({ threshold_for_keeping_unprocessed_records: })
    end

    it 'deletes records older than specified days' do
      stale_event1 = VCAP::CloudController::Event.make(created_at: 1.day.ago - 1.minute)
      stale_event2 = VCAP::CloudController::Event.make(created_at: 2.days.ago)

      fresh_event = VCAP::CloudController::Event.make(created_at: 1.day.ago + 1.minute)

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::Event, 1, threshold_for_keeping_unprocessed_records: Float::INFINITY)

      expect do
        record_cleanup.delete
      end.to change(VCAP::CloudController::Event, :count).by(-2)

      expect(fresh_event.reload).to be_present
      expect { stale_event1.reload }.to raise_error(Sequel::NoExistingObject)
      expect { stale_event2.reload }.to raise_error(Sequel::NoExistingObject)
    end

    context "when there are no records at all but you're trying to keep at least one" do
      it "doesn't keep one because there aren't any to keep" do
        record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::AppEvent, 1, keep_at_least_one_record: true, keep_running_records: true,
                                                                                            keep_unprocessed_records: false,
                                                                                            threshold_for_keeping_unprocessed_records: Float::INFINITY)

        expect { record_cleanup.delete }.not_to raise_error
        expect(VCAP::CloudController::AppEvent.count).to eq(0)
      end
    end

    it 'only retrieves the current timestamp from the database once' do
      expect(VCAP::CloudController::Event.db).to receive(:fetch).with('SELECT CURRENT_TIMESTAMP as now').once.and_call_original
      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::Event, 1, threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
    end

    it 'keeps at least one record' do
      stale_event1 = VCAP::CloudController::Event.make(created_at: 2.days.ago)
      stale_event2 = VCAP::CloudController::Event.make(created_at: 3.days.ago)
      stale_event3 = VCAP::CloudController::Event.make(created_at: 4.days.ago)

      fresh_event = VCAP::CloudController::Event.make(created_at: 1.day.ago + 1.minute)

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::Event, 0, keep_at_least_one_record: true, keep_running_records: true,
                                                                                       keep_unprocessed_records: false,
                                                                                       threshold_for_keeping_unprocessed_records: Float::INFINITY)

      expect do
        record_cleanup.delete
      end.to change(VCAP::CloudController::Event, :count).by(-2)

      expect(fresh_event.reload).to be_present
      expect(stale_event3.reload).to be_present
      expect { stale_event1.reload }.to raise_error(Sequel::NoExistingObject)
      expect { stale_event2.reload }.to raise_error(Sequel::NoExistingObject)
    end

    # Testing keep_running_records feature
    it 'keeps AppUsageEvent start record when there is no corresponding stop record' do
      stale_app_usage_event_start = VCAP::CloudController::AppUsageEvent.make(created_at: 2.days.ago, state: 'STARTED', app_guid: 'guid1')

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::AppUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: true,
                                                                                               keep_unprocessed_records: false,
                                                                                               threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
      expect(stale_app_usage_event_start.reload).to be_present
    end

    it 'keeps AppUsageEvent start record when stop record is fresh' do
      stale_app_usage_event_start = VCAP::CloudController::AppUsageEvent.make(created_at: 2.days.ago, state: 'STARTED', app_guid: 'guid1')
      fresh_app_usage_event_stop = VCAP::CloudController::AppUsageEvent.make(created_at: 1.day.ago + 1.minute, state: 'STOPPED', app_guid: 'guid1')

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::AppUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: true,
                                                                                               keep_unprocessed_records: false,
                                                                                               threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
      expect(stale_app_usage_event_start.reload).to be_present
      expect(fresh_app_usage_event_stop.reload).to be_present
    end

    it 'keeps AppUsageEvent start record when stop record is newer' do
      stale_app_usage_event_stop = VCAP::CloudController::AppUsageEvent.make(created_at: 3.days.ago, state: 'STOPPED', app_guid: 'guid1')
      stale_app_usage_event_start = VCAP::CloudController::AppUsageEvent.make(created_at: 2.days.ago, state: 'STARTED', app_guid: 'guid1')

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::AppUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: true,
                                                                                               keep_unprocessed_records: false,
                                                                                               threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
      expect(stale_app_usage_event_start.reload).to be_present
      expect { stale_app_usage_event_stop.reload }.to raise_error(Sequel::NoExistingObject)
    end

    it 'keeps ServiceUsageEvent create record when there is no corresponding delete record' do
      stale_service_usage_event_create = VCAP::CloudController::ServiceUsageEvent.make(created_at: 2.days.ago, state: 'CREATED', service_instance_guid: 'guid1')

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::ServiceUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: true,
                                                                                                   keep_unprocessed_records: false,
                                                                                                   threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
      expect(stale_service_usage_event_create.reload).to be_present
    end

    it 'keeps ServiceUsageEvent create record when delete record is fresh' do
      stale_service_usage_event_create = VCAP::CloudController::ServiceUsageEvent.make(created_at: 2.days.ago, state: 'CREATED', service_instance_guid: 'guid1')
      fresh_service_usage_event_delete = VCAP::CloudController::ServiceUsageEvent.make(created_at: 1.day.ago + 1.minute, state: 'DELETED', service_instance_guid: 'guid1')

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::ServiceUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: true,
                                                                                                   keep_unprocessed_records: false,
                                                                                                   threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
      expect(stale_service_usage_event_create.reload).to be_present
      expect(fresh_service_usage_event_delete.reload).to be_present
    end

    it 'keeps ServiceUsageEvent create record when delete record is newer' do
      stale_service_usage_event_delete = VCAP::CloudController::ServiceUsageEvent.make(created_at: 3.days.ago, state: 'DELETED', service_instance_guid: 'guid1')
      stale_service_usage_event_create = VCAP::CloudController::ServiceUsageEvent.make(created_at: 2.days.ago, state: 'CREATED', service_instance_guid: 'guid1')

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::ServiceUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: true,
                                                                                                   keep_unprocessed_records: false,
                                                                                                   threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
      expect(stale_service_usage_event_create.reload).to be_present
      expect { stale_service_usage_event_delete.reload }.to raise_error(Sequel::NoExistingObject)
    end

    # Testing keep_unprocessed_records feature
    it 'keeps unprocessed AppUsageEvent records older than the cutoff date' do
      stale_app_usage_event_1_stop = VCAP::CloudController::AppUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', app_guid: 'guid1')
      stale_app_usage_event_2_stop = VCAP::CloudController::AppUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', app_guid: 'guid2')
      VCAP::CloudController::AppUsageConsumer.make(consumer_guid: 'guid1', last_processed_guid: stale_app_usage_event_2_stop.guid)
      stale_app_usage_event_3_stop = VCAP::CloudController::AppUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', app_guid: 'guid3')

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::AppUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: false,
                                                                                               keep_unprocessed_records: true,
                                                                                               threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
      expect { stale_app_usage_event_1_stop.reload }.to raise_error(Sequel::NoExistingObject)
      expect(stale_app_usage_event_2_stop.reload).to be_present
      expect(stale_app_usage_event_3_stop.reload).to be_present
    end

    it 'keeps unprocessed ServiceUsageEvent records older than the cutoff date' do
      stale_service_usage_event_1_stop = VCAP::CloudController::ServiceUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', service_instance_guid: 'guid1')
      stale_service_usage_event_2_stop = VCAP::CloudController::ServiceUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', service_instance_guid: 'guid2')
      VCAP::CloudController::ServiceUsageConsumer.make(consumer_guid: 'guid1', last_processed_guid: stale_service_usage_event_2_stop.guid)
      stale_service_usage_event_3_stop = VCAP::CloudController::ServiceUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', service_instance_guid: 'guid3')

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::ServiceUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: false,
                                                                                                   keep_unprocessed_records: true,
                                                                                                   threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
      expect { stale_service_usage_event_1_stop.reload }.to raise_error(Sequel::NoExistingObject)
      expect(stale_service_usage_event_2_stop.reload).to be_present
      expect(stale_service_usage_event_3_stop.reload).to be_present
    end

    it 'deletes all stale AppUsageEvent records when all registered consumers reference non-existant guids' do
      stale_app_usage_event_1_stop = VCAP::CloudController::AppUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', app_guid: 'guid1')
      stale_app_usage_event_2_stop = VCAP::CloudController::AppUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', app_guid: 'guid2')
      VCAP::CloudController::AppUsageConsumer.make(consumer_guid: 'guid1', last_processed_guid: 'fake-guid-1')
      VCAP::CloudController::AppUsageConsumer.make(consumer_guid: 'guid2', last_processed_guid: 'fake-guid-2')

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::AppUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: false,
                                                                                               keep_unprocessed_records: true,
                                                                                               threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
      expect { stale_app_usage_event_1_stop.reload }.to raise_error(Sequel::NoExistingObject)
      expect { stale_app_usage_event_2_stop.reload }.to raise_error(Sequel::NoExistingObject)
    end

    it 'deletes all stale ServiceUsageEvent records when all registered consumers reference non-existant guids' do
      stale_service_usage_event_1_stop = VCAP::CloudController::ServiceUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', service_instance_guid: 'guid1')
      stale_service_usage_event_2_stop = VCAP::CloudController::ServiceUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', service_instance_guid: 'guid2')
      VCAP::CloudController::ServiceUsageConsumer.make(consumer_guid: 'guid1', last_processed_guid: 'fake-guid-1')
      VCAP::CloudController::ServiceUsageConsumer.make(consumer_guid: 'guid2', last_processed_guid: 'fake-guid-2')

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::ServiceUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: false,
                                                                                                   keep_unprocessed_records: true,
                                                                                                   threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
      expect { stale_service_usage_event_1_stop.reload }.to raise_error(Sequel::NoExistingObject)
      expect { stale_service_usage_event_2_stop.reload }.to raise_error(Sequel::NoExistingObject)
    end

    it 'deletes stale AppUsageEvent records even if 1 consumer references a non-existant guid' do
      stale_app_usage_event_1_stop = VCAP::CloudController::AppUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', app_guid: 'guid1')
      stale_app_usage_event_2_stop = VCAP::CloudController::AppUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', app_guid: 'guid2')
      VCAP::CloudController::AppUsageConsumer.make(consumer_guid: 'guid1', last_processed_guid: 'fake-guid-1')
      VCAP::CloudController::AppUsageConsumer.make(consumer_guid: 'guid2', last_processed_guid: stale_app_usage_event_2_stop.guid)

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::AppUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: false,
                                                                                               keep_unprocessed_records: true,
                                                                                               threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
      expect { stale_app_usage_event_1_stop.reload }.to raise_error(Sequel::NoExistingObject)
      expect(stale_app_usage_event_2_stop.reload).to be_present
    end

    it 'deletes stale ServiceUsageEvent records even if 1 consumer references a non-existant guid' do
      stale_service_usage_event_1_stop = VCAP::CloudController::ServiceUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', service_instance_guid: 'guid1')
      stale_service_usage_event_2_stop = VCAP::CloudController::ServiceUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', service_instance_guid: 'guid2')
      VCAP::CloudController::ServiceUsageConsumer.make(consumer_guid: 'guid1', last_processed_guid: 'fake-guid-1')
      VCAP::CloudController::ServiceUsageConsumer.make(consumer_guid: 'guid2', last_processed_guid: stale_service_usage_event_2_stop.guid)

      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::ServiceUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: false,
                                                                                                   keep_unprocessed_records: true,
                                                                                                   threshold_for_keeping_unprocessed_records: Float::INFINITY)
      record_cleanup.delete
      expect { stale_service_usage_event_1_stop.reload }.to raise_error(Sequel::NoExistingObject)
      expect(stale_service_usage_event_2_stop.reload).to be_present
    end

    context 'when table size exceeds limit' do
      let(:model) { VCAP::CloudController::AppUsageEvent }

      before do
        allow(model.db).to receive(:fetch).with("SELECT COUNT(*) as count FROM #{model.table_name}").and_return([{ count: threshold_for_keeping_unprocessed_records + 1 }])
        allow(model.db).to receive(:fetch).with('SELECT CURRENT_TIMESTAMP as now').and_call_original
      end

      it 'performs size-based cleanup' do
        record_cleanup = Database::OldRecordCleanup.new(model, cutoff_age_in_days, threshold_for_keeping_unprocessed_records:)
        expect(Steno.logger('cc.old_record_cleanup')).to receive(:info).with(/exceeds size limit of #{threshold_for_keeping_unprocessed_records} rows/)
        expect(Steno.logger('cc.old_record_cleanup')).to receive(:info).with(/Cleaning up \d+ #{model.table_name} table rows \(size-based cleanup\)/)
        record_cleanup.delete
      end
    end

    context 'when table size is within limit' do
      let(:model) { VCAP::CloudController::AppUsageEvent }

      before do
        allow(model.db).to receive(:fetch).with("SELECT COUNT(*) as count FROM #{model.table_name}").and_return([{ count: threshold_for_keeping_unprocessed_records - 1 }])
        allow(model.db).to receive(:fetch).with('SELECT CURRENT_TIMESTAMP as now').and_call_original
      end

      it 'performs normal cleanup' do
        record_cleanup = Database::OldRecordCleanup.new(model, cutoff_age_in_days, threshold_for_keeping_unprocessed_records:)
        expect(Steno.logger('cc.old_record_cleanup')).to receive(:info).with(/Cleaning up \d+ #{model.table_name} table rows \(normal cleanup\)/)
        record_cleanup.delete
      end
    end

    context 'when table is not a usage event table' do
      let(:model) { VCAP::CloudController::Event }

      before do
        allow(model.db).to receive(:fetch).with('SELECT CURRENT_TIMESTAMP as now').and_call_original
      end

      it 'performs normal cleanup' do
        record_cleanup = Database::OldRecordCleanup.new(model, cutoff_age_in_days, threshold_for_keeping_unprocessed_records: Float::INFINITY)
        expect(Steno.logger('cc.old_record_cleanup')).to receive(:info).with(/Cleaning up \d+ #{model.table_name} table rows \(normal cleanup\)/)
        record_cleanup.delete
      end
    end
  end
end

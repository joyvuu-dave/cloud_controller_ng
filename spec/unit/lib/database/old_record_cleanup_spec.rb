require 'spec_helper'
require 'database/old_record_cleanup'

RSpec.describe Database::OldRecordCleanup do
  describe '#delete' do
    let!(:stale_event1) { VCAP::CloudController::Event.make(created_at: 1.day.ago - 1.minute) }
    let!(:stale_event2) { VCAP::CloudController::Event.make(created_at: 2.days.ago) }

    let!(:fresh_event) { VCAP::CloudController::Event.make(created_at: 1.day.ago + 1.minute) }

    let!(:stale_app_usage_event_1_start) { VCAP::CloudController::AppUsageEvent.make(created_at: 2.days.ago, state: 'STARTED', app_guid: 'guid1') }

    let!(:stale_app_usage_event_2_start) { VCAP::CloudController::AppUsageEvent.make(created_at: 2.days.ago, state: 'STARTED', app_guid: 'guid2') }
    let!(:fresh_app_usage_event_2_stop) { VCAP::CloudController::AppUsageEvent.make(created_at: 1.day.ago + 1.minute, state: 'STOPPED', app_guid: 'guid2') }

    let!(:stale_app_usage_event_3_stop) { VCAP::CloudController::AppUsageEvent.make(created_at: 3.days.ago, state: 'STOPPED', app_guid: 'guid3') }
    let!(:stale_app_usage_event_3_start) { VCAP::CloudController::AppUsageEvent.make(created_at: 2.days.ago, state: 'STARTED', app_guid: 'guid3') }

    let!(:stale_service_usage_event_1_create) { VCAP::CloudController::ServiceUsageEvent.make(created_at: 2.days.ago, state: 'CREATED', service_instance_guid: 'guid1') }

    let!(:stale_service_usage_event_2_create) { VCAP::CloudController::ServiceUsageEvent.make(created_at: 2.days.ago, state: 'CREATED', service_instance_guid: 'guid2') }
    let!(:fresh_service_usage_event_2_delete) { VCAP::CloudController::ServiceUsageEvent.make(created_at: 1.day.ago + 1.minute, state: 'DELETED', service_instance_guid: 'guid2') }

    let!(:stale_service_usage_event_3_delete) { VCAP::CloudController::ServiceUsageEvent.make(created_at: 3.days.ago, state: 'DELETED', service_instance_guid: 'guid3') }
    let!(:stale_service_usage_event_3_create) { VCAP::CloudController::ServiceUsageEvent.make(created_at: 2.days.ago, state: 'CREATED', service_instance_guid: 'guid3') }

    let!(:stale_app_usage_event_4_stop) { VCAP::CloudController::AppUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', app_guid: 'guid4') }
    let!(:stale_app_usage_event_5_stop) { VCAP::CloudController::AppUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', app_guid: 'guid5') }
    let!(:app_usage_consumer) { VCAP::CloudController::AppUsageConsumer.make(consumer_guid: 'guid1', last_processed_guid: stale_app_usage_event_5_stop) }
    let!(:stale_app_usage_event_6_stop) { VCAP::CloudController::AppUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', app_guid: 'guid6') }

    let!(:stale_service_usage_event_4_stop) { VCAP::CloudController::ServiceUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', service_instance_guid: 'guid4') }
    let!(:stale_service_usage_event_5_stop) { VCAP::CloudController::ServiceUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', service_instance_guid: 'guid5') }
    let!(:service_usage_consumer) { VCAP::CloudController::ServiceUsageConsumer.make(consumer_guid: 'guid1', last_processed_guid: stale_service_usage_event_5_stop) }
    let!(:stale_service_usage_event_6_stop) { VCAP::CloudController::ServiceUsageEvent.make(created_at: 1.year.ago, state: 'STOPPED', service_instance_guid: 'guid6') }

    it 'deletes records older than specified days' do
      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::Event, 1)

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
                                                                                            keep_unprocessed_records: false)

        expect { record_cleanup.delete }.not_to raise_error
        expect(VCAP::CloudController::AppEvent.count).to eq(0)
      end
    end

    it 'only retrieves the current timestamp from the database once' do
      expect(VCAP::CloudController::Event.db).to receive(:fetch).with('SELECT CURRENT_TIMESTAMP as now').once.and_call_original
      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::Event, 1)
      record_cleanup.delete
    end

    it 'keeps the last row when :keep_at_least_one_record is true even if it is older than the cutoff date' do
      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::Event, 0, keep_at_least_one_record: true, keep_running_records: true, keep_unprocessed_records: false)

      expect do
        record_cleanup.delete
      end.to change(VCAP::CloudController::Event, :count).by(-2)

      expect(fresh_event.reload).to be_present
      expect { stale_event1.reload }.to raise_error(Sequel::NoExistingObject)
      expect { stale_event2.reload }.to raise_error(Sequel::NoExistingObject)
    end

    # Testing keep_running_records feature
    it 'keeps AppUsageEvent start record when there is no corresponding stop record' do
      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::AppUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: true,
                                                                                               keep_unprocessed_records: false)
      record_cleanup.delete
      expect(stale_app_usage_event_1_start.reload).to be_present
    end

    it 'keeps AppUsageEvent start record when stop record is fresh' do
      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::AppUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: true,
                                                                                               keep_unprocessed_records: false)
      record_cleanup.delete
      expect(stale_app_usage_event_2_start.reload).to be_present
      expect(fresh_app_usage_event_2_stop.reload).to be_present
    end

    it 'keeps AppUsageEvent start record when stop record is newer' do
      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::AppUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: true,
                                                                                               keep_unprocessed_records: false)
      record_cleanup.delete
      expect(stale_app_usage_event_3_start.reload).to be_present
      expect { stale_app_usage_event_3_stop.reload }.to raise_error(Sequel::NoExistingObject)
    end

    it 'keeps ServiceUsageEvent create record when there is no corresponding delete record' do
      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::ServiceUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: true,
                                                                                                   keep_unprocessed_records: false)
      record_cleanup.delete
      expect(stale_service_usage_event_1_create.reload).to be_present
    end

    it 'keeps ServiceUsageEvent create record when delete record is fresh' do
      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::ServiceUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: true,
                                                                                                   keep_unprocessed_records: false)
      record_cleanup.delete
      expect(stale_service_usage_event_2_create.reload).to be_present
      expect(fresh_service_usage_event_2_delete.reload).to be_present
    end

    it 'keeps ServiceUsageEvent create record when delete record is newer' do
      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::ServiceUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: true,
                                                                                                   keep_unprocessed_records: false)
      record_cleanup.delete
      expect(stale_service_usage_event_3_create.reload).to be_present
      expect { stale_service_usage_event_3_delete.reload }.to raise_error(Sequel::NoExistingObject)
    end

    # Testing keep_unprocessed_records feature
    it 'keeps unprocessed AppUsageEvent records older than the cutoff date' do
      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::AppUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: false,
                                                                                               keep_unprocessed_records: true)
      record_cleanup.delete
      expect { stale_app_usage_event_4_stop.reload }.to raise_error(Sequel::NoExistingObject)
      expect(stale_app_usage_event_5_stop.reload).to be_present
      expect(stale_app_usage_event_6_stop.reload).to be_present
    end

    it 'keeps unprocessed ServiceUsageEvent records older than the cutoff date' do
      record_cleanup = Database::OldRecordCleanup.new(VCAP::CloudController::ServiceUsageEvent, 1, keep_at_least_one_record: false, keep_running_records: false,
                                                                                                   keep_unprocessed_records: true)
      record_cleanup.delete
      expect { stale_service_usage_event_4_stop.reload }.to raise_error(Sequel::NoExistingObject)
      expect(stale_service_usage_event_5_stop.reload).to be_present
      expect(stale_service_usage_event_6_stop.reload).to be_present
    end
  end
end

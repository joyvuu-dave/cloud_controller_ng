require 'database/batch_delete'

module Database
  class OldRecordCleanup
    class NoCurrentTimestampError < StandardError; end
    attr_reader :model, :cutoff_age_in_days, :keep_at_least_one_record, :keep_running_records, :keep_unprocessed_records

    def initialize(model, cutoff_age_in_days, keep_at_least_one_record: false, keep_running_records: false, keep_unprocessed_records: false)
      @model = model
      @cutoff_age_in_days = cutoff_age_in_days
      @keep_at_least_one_record = keep_at_least_one_record
      @keep_running_records = keep_running_records
      @keep_unprocessed_records = keep_unprocessed_records
    end

    def delete
      if should_enforce_size_limit?
        # Size-based cleanup - ignore keep_running_records and keep_unprocessed_records
        perform_size_based_cleanup
      else
        # Normal date-based cleanup with all the usual protections
        perform_normal_cleanup
      end
    end

    private

    def logger
      @logger ||= Steno.logger('cc.old_record_cleanup')
    end

    def max_usage_event_rows
      VCAP::CloudController::Config.config.get(:app_usage_events).fetch(:max_usage_event_rows, 5_000_000)
    end

    def should_enforce_size_limit?
      return false unless usage_event_model?
      row_count = approximate_row_count(model)
      if row_count > max_usage_event_rows
        logger.info("Table #{model.table_name} exceeds size limit of #{max_usage_event_rows} rows")
        true
      else
        false
      end
    end

    def perform_size_based_cleanup
      cutoff_date = current_timestamp_from_database - cutoff_age_in_days.to_i.days
      old_records = model.dataset.where(Sequel.lit('created_at < ?', cutoff_date))

      if keep_at_least_one_record
        last_record = model.order(:id).last
        old_records = old_records.where(Sequel.lit('id < ?', last_record.id)) if last_record
      end

      # Find any consumers that would be affected by this purge
      affected_consumers = find_affected_consumers(old_records)

      # Remove those consumer records - they'll need to re-register
      remove_affected_consumers(affected_consumers) if affected_consumers.any?

      logger.info("Cleaning up #{old_records.count} #{model.table_name} table rows (size-based cleanup)")
      Database::BatchDelete.new(old_records, 1000).delete
    end

    def perform_normal_cleanup
      cutoff_date = current_timestamp_from_database - cutoff_age_in_days.to_i.days
      old_records = model.dataset.where(Sequel.lit('created_at < ?', cutoff_date))

      old_records = apply_cleanup_filters(old_records)

      logger.info("Cleaning up #{old_records.count} #{model.table_name} table rows (normal cleanup)")
      Database::BatchDelete.new(old_records, 1000).delete
    end

    def apply_cleanup_filters(dataset)
      if keep_at_least_one_record
        last_record = model.order(:id).last
        dataset = dataset.where(Sequel.lit('id < ?', last_record.id)) if last_record
      end

      if keep_running_records && model.columns.include?(:state)
        dataset = dataset.exclude(state: 'STARTED')
      end

      if keep_unprocessed_records && usage_event_model?
        consumer_model = registered_consumer_model(model)
        if consumer_model
          consumers = consumer_model.all
          consumers.each do |consumer|
            dataset = dataset.exclude(guid: consumer.last_processed_guid)
          end
        end
      end

      dataset
    end

    def find_affected_consumers(records_to_delete)
      consumer_model = registered_consumer_model(model)
      return [] unless consumer_model

      # Find consumers whose last_processed_guid is in the records we're about to delete
      consumer_model.where(last_processed_guid: records_to_delete.select(:guid))
    end

    def remove_affected_consumers(consumers)
      logger.info("Removing #{consumers.count} affected consumers due to size-based cleanup")
      consumers.delete
    end

    def approximate_row_count(model)
      case model.db.database_type
      when :postgres
        # Lightning fast - just reads statistics
        result = model.db[<<-SQL
          SELECT reltuples::bigint AS estimate
          FROM pg_class
          WHERE relname = '#{model.table_name}'
        SQL
        ].first
        result[:estimate].to_i
      when :mysql, :mysql2
        # Also quite fast - reads information_schema
        result = model.db[<<-SQL
          SELECT table_rows
          FROM information_schema.tables
          WHERE table_schema = DATABASE()
            AND table_name = '#{model.table_name}'
        SQL
        ].first
        result[:table_rows].to_i
      end
    end

    def current_timestamp_from_database
      @current_timestamp ||= begin
        now = model.db.fetch('SELECT CURRENT_TIMESTAMP as now').first[:now]
        Time.zone ? Time.zone.parse(now.to_s) : now
      end
    end

    def usage_event_model?
      model == VCAP::CloudController::AppUsageEvent || model == VCAP::CloudController::ServiceUsageEvent
    end

    def registered_consumer_model(model)
      return VCAP::CloudController::AppUsageConsumer if model == VCAP::CloudController::AppUsageEvent && VCAP::CloudController::AppUsageConsumer.present?
      return VCAP::CloudController::ServiceUsageConsumer if model == VCAP::CloudController::ServiceUsageEvent && VCAP::CloudController::ServiceUsageConsumer.present?
      nil
    end
  end
end

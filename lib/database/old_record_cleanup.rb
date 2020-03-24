require 'database/batch_delete'

module Database
  class OldRecordCleanup
    class NoCurrentTimestampError < StandardError; end
    attr_reader :model, :days_ago, :keep_at_least_one_day_of_records

    def initialize(model, days_ago, keep_at_least_one_day_of_records: false)
      @model = model
      @days_ago = days_ago
      @keep_at_least_one_day_of_records = keep_at_least_one_day_of_records
    end

    def delete
      cutoff_date = current_timestamp_from_database - days_ago.to_i.days

      old_records = model.dataset.where(Sequel.lit('created_at < ?', cutoff_date))
      if keep_at_least_one_day_of_records
        last_created_at = model.order(:id).last.created_at
        one_day_cutoff_date = last_created_at - 1.days
        old_records = old_records.where(Sequel.lit('created_at < ?', one_day_cutoff_date))
      end
      logger.info("Cleaning up #{old_records.count} #{model.table_name} table rows")

      Database::BatchDelete.new(old_records, 1000).delete
    end

    private

    def current_timestamp_from_database
      # Evaluate the cutoff data upfront using the database's current time so that it remains the same
      # for each iteration of the batched delete
      model.db.fetch('SELECT CURRENT_TIMESTAMP as now').first[:now]
    end

    def logger
      @logger ||= Steno.logger('cc.old_record_cleanup')
    end
  end
end

class TableTruncator
  def initialize(db, tables=nil)
    @db = db
    @tables = tables || self.class.isolated_tables(db)
  end

  def self.isolated_tables(db)
    db.tables - [:schema_migrations]
  end

  def truncate_tables
    case db.database_type
    when :postgres
      referential_integrity = ReferentialIntegrity.new(db)
      referential_integrity.without do
        tables.each do |table|
          db.run("TRUNCATE TABLE #{table} RESTART IDENTITY CASCADE;")
        end
      end
    when :mysql
      # Use db.synchronize to ensure SET FOREIGN_KEY_CHECKS and all TRUNCATE
      # statements run on the SAME connection from the pool. Without this,
      # each db.run() can get a different connection, and SET FOREIGN_KEY_CHECKS=0
      # (which is session-specific) won't apply to the TRUNCATE statements.
      db.synchronize do |conn|
        conn.query('SET FOREIGN_KEY_CHECKS = 0')
        tables.each do |table|
          conn.query("TRUNCATE TABLE #{table}")
        end
        conn.query('SET FOREIGN_KEY_CHECKS = 1')
      end
    end
  end

  private

  attr_reader :db, :tables
end

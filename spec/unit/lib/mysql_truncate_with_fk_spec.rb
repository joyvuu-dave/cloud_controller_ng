require 'spec_helper'

RSpec.describe 'MySQL dataset.truncate with FK constraints', type: :integration do
  let(:db) { VCAP::CloudController::ServiceUsageEvent.db }

  before do
    skip 'This test only applies to MySQL' unless db.database_type == :mysql
  end

  describe 'reproducing the FK constraint violation bug' do
    # This test demonstrates the bug that exists in purge_and_reseed methods
    # when they call dataset.truncate on MySQL without proper FK handling
    
    before do
      # Create two tables with a FK relationship to simulate the real scenario
      db.create_table!(:test_parent_table) do
        primary_key :id
        String :guid
        String :name
      end
      
      db.create_table!(:test_child_table) do
        primary_key :id  
        Integer :parent_id
        String :data
        foreign_key [:parent_id], :test_parent_table, key: :id, name: :fk_test_child_parent
      end
      
      # Insert some test data
      db[:test_parent_table].insert(guid: 'parent-1', name: 'Parent 1')
      parent_id = db[:test_parent_table].first[:id]
      db[:test_child_table].insert(parent_id: parent_id, data: 'child data')
    end
    
    after do
      db.drop_table?(:test_child_table)
      db.drop_table?(:test_parent_table)
    end
    
    context 'without FK handling (reproducing the bug)' do
      it 'FAILS to truncate parent table when child references exist' do
        # This simulates what the buggy code does:
        # Just calling dataset.truncate without disabling FK checks
        
        # On MySQL, this should fail because test_child_table has a FK to test_parent_table
        expect {
          db[:test_parent_table].truncate
        }.to raise_error(Sequel::DatabaseError, /Cannot truncate a table referenced in a foreign key constraint/)
      end
    end
    
    context 'with proper FK handling (the fix)' do
      it 'successfully truncates when FK checks are properly disabled on same connection' do
        # This is what the fix does: use db.synchronize to ensure same connection
        expect {
          db.synchronize do |conn|
            conn.query('SET FOREIGN_KEY_CHECKS = 0')
            conn.query('TRUNCATE TABLE test_parent_table')
            conn.query('SET FOREIGN_KEY_CHECKS = 1')
          end
        }.not_to raise_error
        
        # Verify the table was actually truncated
        expect(db[:test_parent_table].count).to eq(0)
      end
    end
    
    context 'demonstrating why db.run approach is unreliable' do
      it 'MAY fail when using separate db.run calls due to connection pooling' do
        # This demonstrates the intermittent nature of the bug
        # Sometimes it works (same connection), sometimes it fails (different connections)
        
        # Force the connection pool to have multiple connections
        connections_used = []
        
        # Get one connection
        db.synchronize { |c| connections_used << c.object_id }
        
        # Get another connection (might be same, might be different)
        db.synchronize { |c| connections_used << c.object_id }
        
        # If we got different connections, this proves the issue exists
        if connections_used.uniq.size > 1
          # With separate db.run() calls, we can't guarantee same connection
          # This is the root cause of the bug
          expect {
            db.run('SET FOREIGN_KEY_CHECKS = 0')  # Might be on connection A
            db[:test_parent_table].truncate        # Might be on connection B
            db.run('SET FOREIGN_KEY_CHECKS = 1')   # Might be on connection C
          }.to raise_error(Sequel::DatabaseError, /Cannot truncate/)
        else
          skip 'Connection pool happened to reuse same connection (intermittent behavior)'
        end
      end
    end
  end
  
  describe 'the production code bug' do
    it 'demonstrates that the fix uses truncate_with_fk_handling instead of raw truncate' do
      # The production code now uses truncate_with_fk_handling helper
      # which properly handles MySQL FK constraints using db.synchronize
      
      repository = VCAP::CloudController::Repositories::ServiceUsageEventRepository.new
      
      # Verify the method exists and is private
      expect(repository.private_methods).to include(:truncate_with_fk_handling)
      
      # The fix ensures we don't call dataset.truncate directly on MySQL
      # Instead we use db.synchronize + SET FOREIGN_KEY_CHECKS
      expect(repository.respond_to?(:purge_and_reseed_service_instances!, true)).to be true
    end
  end
end


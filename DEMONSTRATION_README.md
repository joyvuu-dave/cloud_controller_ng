# MySQL FK Constraint Fix Demonstration

## Quick Start

Run the demonstration script:

```bash
./demonstrate_mysql_fk_fix.sh
```

This interactive script will walk you through proving the bug and the fix.

## What the Script Does

### Part 1: Demonstrates the Bug Exists
- Runs tests that prove `dataset.truncate` fails with FK constraints
- Shows that without proper FK handling, MySQL throws errors
- **Test Section**: "without FK handling (reproducing the bug)"
  - Creates two tables with FK relationship
  - Attempts to TRUNCATE parent table
  - **Expected**: Fails with FK constraint error ✓
  - **Result**: PASSES (because the test expects the error)

### Part 2: Shows Why db.run() is Unreliable  
- **Test Section**: "demonstrating why db.run approach is unreliable"
  - Shows connection pooling causes different connections
  - Proves `SET FOREIGN_KEY_CHECKS` on one connection doesn't affect another
  - **Expected**: May fail intermittently
  - **Result**: Demonstrates the race condition

### Part 3: Proves the Fix Works
- **Test Section**: "with proper FK handling (the fix)"
  - Uses `db.synchronize` to hold single connection
  - Executes `SET FOREIGN_KEY_CHECKS=0` + TRUNCATE + restore on same connection
  - **Expected**: Succeeds ✓
  - **Result**: PASSES reliably

## Prerequisites

1. **Docker installed and running**
2. **MySQL container available**:
   ```bash
   docker-compose up -d mysql
   ```
3. **Bundle installed**:
   ```bash
   bundle install
   ```

## Manual Test Commands

If you want to run tests manually:

### Run the demonstration test:
```bash
DB=mysql \
MYSQL_CONNECTION_PREFIX="mysql2://root:supersecret@127.0.0.1:3306" \
bundle exec rspec spec/unit/lib/mysql_truncate_with_fk_spec.rb \
  --format documentation \
  --color
```

### Run the actual repository tests:
```bash
DB=mysql \
MYSQL_CONNECTION_PREFIX="mysql2://root:supersecret@127.0.0.1:3306" \
bundle exec rspec spec/unit/repositories/service_usage_event_repository_spec.rb \
  -e "purge_and_reseed"
```

## Understanding the Test Output

### ✅ Expected PASS:
```
MySQL dataset.truncate with FK constraints
  reproducing the FK constraint violation bug
    without FK handling (reproducing the bug)
      FAILS to truncate parent table when child references exist (PASSED)
```
**Why it passes**: The test EXPECTS a FK error, proving the bug exists

### ✅ Expected PASS:
```
    with proper FK handling (the fix)
      successfully truncates when FK checks are properly disabled (PASSED)
```
**Why it passes**: The fix works correctly

### ⚠️ May be Intermittent:
```
    demonstrating why db.run approach is unreliable
      MAY fail when using separate db.run calls (SKIPPED or PASSED)
```
**Why**: Connection pool behavior is non-deterministic

## Test File Details

**Location**: `spec/unit/lib/mysql_truncate_with_fk_spec.rb`

**What it tests**:
1. Creates test tables with FK relationships
2. Attempts TRUNCATE without FK handling → expects failure
3. Attempts TRUNCATE with proper FK handling → expects success
4. Demonstrates connection pooling causes the issue

## The Fix Explained

### Without Fix (Buggy):
```ruby
def purge_and_reseed_service_instances!
  ServiceUsageEvent.dataset.truncate  # ← May fail with FK errors
end
```

### With Fix (Correct):
```ruby
def purge_and_reseed_service_instances!
  truncate_with_fk_handling(ServiceUsageEvent.dataset)
end

private

def truncate_with_fk_handling(dataset)
  db = dataset.db
  case db.database_type
  when :mysql
    db.synchronize do |conn|  # ← Hold same connection
      conn.query('SET FOREIGN_KEY_CHECKS = 0')
      conn.query("TRUNCATE TABLE #{dataset.first_source_table}")
      conn.query('SET FOREIGN_KEY_CHECKS = 1')
    end
  when :postgres
    dataset.truncate  # PostgreSQL CASCADE handles this
  end
end
```

## Why This Matters

These methods are exposed as **production API endpoints**:
- `POST /v3/service_usage_events/actions/destructively_purge_all_and_reseed`
- `POST /v3/app_usage_events/actions/destructively_purge_all_and_reseed`

Used by operators to create billing epochs. Without this fix, these APIs would fail on MySQL deployments.

## Troubleshooting

### MySQL not running?
```bash
docker-compose up -d mysql
sleep 15  # Wait for startup
```

### Connection refused?
Check the connection string matches your MySQL setup:
```bash
mysql -h 127.0.0.1 -P 3306 -uroot -psupersecret
```

### Tests still passing when they should fail?
The connection pool might be reusing the same connection (intermittent behavior). This is why the original bug was hard to reproduce consistently.

## Questions?

See the full analysis in:
- `BUG_ANALYSIS.md` - Complete analysis for the team
- `MYSQL_FK_FIX_SUMMARY.md` - Technical summary


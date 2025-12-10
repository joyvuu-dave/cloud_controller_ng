# MySQL FK Constraint Fix for dataset.truncate

## Problem Statement

The `purge_and_reseed_service_instances!` and `purge_and_reseed_started_apps!` methods in the repository classes call `dataset.truncate` directly without handling MySQL foreign key constraints.

On MySQL, attempting to TRUNCATE a table that is referenced by a foreign key constraint will fail with:
```
Mysql2::Error: Cannot truncate a table referenced in a foreign key constraint
```

## Root Cause

MySQL's `FOREIGN_KEY_CHECKS` setting is **session-specific**. When using Sequel's connection pool:
- Each `db.run()` call can get a different connection from the pool
- Setting `FOREIGN_KEY_CHECKS=0` on one connection doesn't affect other connections
- Therefore, the TRUNCATE might execute on a different connection that still has FK checks enabled

## The Fix

Use `db.synchronize` to ensure all operations run on the **same connection**:

```ruby
def truncate_with_fk_handling(dataset)
  db = dataset.db
  case db.database_type
  when :postgres
    dataset.truncate  # PostgreSQL CASCADE handles this
  when :mysql
    db.synchronize do |conn|
      conn.query('SET FOREIGN_KEY_CHECKS = 0')
      conn.query("TRUNCATE TABLE #{dataset.first_source_table}")
      conn.query('SET FOREIGN_KEY_CHECKS = 1')
    end
  end
end
```

## Test Strategy

The test (`spec/unit/lib/mysql_truncate_with_fk_spec.rb`) demonstrates:

1. **The bug exists**: Attempting to TRUNCATE a table with FK references fails
2. **The fix works**: Using `db.synchronize` with proper FK handling succeeds  
3. **Why it's unreliable**: Connection pooling makes separate `db.run()` calls use different connections

## Why This Affects Production

These methods are exposed as production API endpoints:
- `POST /v3/service_usage_events/actions/destructively_purge_all_and_reseed`
- `POST /v3/app_usage_events/actions/destructively_purge_all_and_reseed`

Used by operators to create billing epochs. Without this fix, these APIs would fail on MySQL deployments.

## Files Changed

- `app/repositories/service_usage_event_repository.rb` - Add `truncate_with_fk_handling` helper
- `app/repositories/app_usage_event_repository.rb` - Add `truncate_with_fk_handling` helper
- `spec/unit/lib/mysql_truncate_with_fk_spec.rb` - Test demonstrating bug and fix


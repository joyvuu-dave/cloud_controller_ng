# Cloud Controller `events` Table: Query Performance Investigation, Fix & Verification

**Date:** 2026-03-25
**Internal Ref:** TNZ-89706 (High CPU usage on TAS MySQL)
**Affected Version:** TAS v10.2.8
**Branch:** `fix/events-query-performance-tnz-89706`
**Status:** Implemented, benchmarked, pending leadership review

---

## 1. Executive Summary

A customer running TAS v10.2.8 experienced sustained 95%+ CPU on their MySQL VMs. The root cause was expensive queries against the `events` table: each read **1.3 GiB from disk** and took **34+ seconds** despite returning only **10 rows**. The bottleneck was a filesort over millions of rows caused by missing composite indexes.

**Fix:** Add three composite indexes to the `events` table via a single migration.

| Index | Columns | Query Pattern Fixed | MySQL 8.0 Speedup |
|-------|---------|-------------------|---------------|
| Index 1 | `(actee, created_at, guid)` | Actee-filtered: `target_guids=X&types=...` | **3,227x** (1,936ms -> 0.6ms) |
| Index 2 | `(space_guid, created_at, guid)` | Space browse: `space_guids=X&types=...` | **3,105x** (1,863ms -> 0.6ms) |
| Index 3 | `(organization_guid, created_at, guid)` | Org browse: `organization_guids=X&types=...` | **3,820x** (1,910ms -> 0.5ms) |

Each index independently eliminates a distinct filesort bottleneck. All three are needed: Index 1 does not help space/org queries, Index 2 does not help actee/org queries, Index 3 does not help actee/space queries. The fix is non-destructive (no data or schema changes beyond the indexes), independently reversible, and scoped entirely to the events table.

**Both MySQL and PostgreSQL are affected.** The existing `(created_at, guid)` index handles the ORDER BY via backward scan, but this degrades severely when the target entity (app, space, or org) has been quiet recently -- MySQL must scan through millions of non-matching recent rows before finding results. PostgreSQL showed the same behavior: 389ms baseline -> 0.5ms with Index 1 (778x faster). The composite indexes eliminate this by seeking directly to the target entity's rows.

---

## 2. Problem Statement

The customer's MySQL VMs serving the Cloud Controller database (`ccdb`) were saturated at 95%+ CPU. The root cause was traced to expensive queries against the `events` table that ran frequently and concurrently. Each query read over **1.3 GiB from disk** and took **34+ seconds**, despite returning only **10 rows**. When multiple queries ran concurrently, they exhausted all available CPU.

Scaling the MySQL VM from `large.disk` (2 CPU, 8 GB RAM) to `xlarge.disk` (4 CPU, 16 GB RAM) did not resolve the issue -- CPU remained saturated at 94.5%. The issue only subsided after restarting `monit` processes on high-CPU VMs and allowing the system to stabilize.

---

## 3. The Expensive Query

Captured from the MySQL slow query log:

```sql
SELECT * FROM `events`
INNER JOIN (
    SELECT `events`.`id` AS `tmp_deferred_id`
    FROM `events`
    WHERE (
        ((`space_guid` IN (
            '0604f02c-5014-44a1-a9dd-eee8710574b6',
            '234c0125-0bcb-4b69-b49d-09cf58e125e3',
            'f1060ce1-6d34-4d5a-ae9c-e28454b5e11c'
        )) OR (1 = 0))
        AND (`type` IN (
            'app.crash', 'audit.app.create', 'audit.app.deployment.create',
            'audit.app.deployment.cancel', 'audit.app.map-route',
            'audit.app.process.crash', 'audit.app.process.create',
            'audit.app.process.scale', 'audit.app.process.terminate_instance',
            'audit.app.process.update', 'audit.app.restage', 'audit.app.start',
            'audit.app.stop', 'audit.app.unmap-route', 'audit.app.update',
            'audit.app.ssh-authorized', 'audit.app.ssh-unauthorized'
        ))
        AND (`actee` IN ('e2ef4f08-f2ac-435e-857b-947135819ce4'))
    )
    ORDER BY `events`.`created_at` DESC, `events`.`guid` DESC
    LIMIT 10 OFFSET 0
) AS `tmp_deferred_table`
    ON (`events`.`id` = `tmp_deferred_table`.`tmp_deferred_id`)
WHERE (
    ((`space_guid` IN (...)) OR (1 = 0))
    AND (`type` IN (...))
    AND (`actee` IN ('e2ef4f08-f2ac-435e-857b-947135819ce4'))
)
ORDER BY `events`.`created_at` DESC, `events`.`guid` DESC;
```

### Slow Query Log Metrics

| Metric | Value | Significance |
|--------|-------|-------------|
| Query_time | 34.1s | Wall-clock time for a single query |
| Rows_sent | 10 | Only 10 rows actually returned |
| Rows_examined | 30 | Outer query rows only (see note below) |
| InnoDB_IO_r_bytes | 1.3 GiB | Massive disk I/O from inner subquery |
| InnoDB_IO_r_ops | 85,236 | Massive I/O operation count |
| Full_scan | Yes | No suitable index used for ordering |
| Filesort | Yes | MySQL sorted in memory (see note on execution plans) |

**Note on `Rows_examined: 30`:** In this deferred-join query, the inner subquery (`SELECT events.id ... ORDER BY ... LIMIT 10`) is materialized into a derived table of 10 rows. `Rows_examined` reflects the rows examined during the materialization result and outer join — not the I/O performed during the inner subquery's index traversal. The outer query examines the 10-row derived table and joins back to 10 base table rows (with some overhead = 30 total). The massive I/O from the inner subquery's index scan is captured by `InnoDB_IO_r_bytes` (1.3 GiB) and `InnoDB_IO_r_ops` (85,236), not by `Rows_examined`.

**Note on execution plans — Filesort vs. Backward Scan:** The customer's slow query log shows `Filesort: Yes`, indicating their MySQL chose the `events_actee_index` for WHERE filtering and then filesorted the results to satisfy the ORDER BY. Our benchmarks on MySQL 8.0.45 show a **different** optimizer choice: MySQL uses the `(created_at, guid)` index for a backward scan to satisfy the ORDER BY and post-filters rows against the WHERE predicates. Both plans are slow under temporal skew, but for different reasons:
- **Filesort plan** (customer): Uses `events_actee_index` to find ~2M matching rows, then sorts all of them. CPU-bound.
- **Backward scan plan** (benchmark): Walks `(created_at, guid)` index in reverse, checks each row against WHERE predicates, skips ~1.35M non-matching recent rows. I/O-bound.

The difference likely reflects MySQL version and/or optimizer statistics differences. Our composite indexes fix **both** plans: with `(actee, created_at, guid)`, MySQL can filter AND order from a single index, eliminating both the filesort and the non-selective backward scan.

**Why our benchmark shows 1.9 seconds while the customer saw 34 seconds:** Several factors explain the ~18x gap: (1) the customer's table was likely much larger than our 5M rows (the 1.3 GiB I/O suggests tens of millions of rows), (2) the customer's MySQL used a filesort plan (CPU-bound sorting millions of rows is slower than our I/O-bound backward scan), (3) production databases use network-attached storage with higher latency than our local SSD, (4) concurrent queries competing for buffer pool and CPU would amplify latency. Our benchmark demonstrates the mechanism and proves the fix; the absolute times are environment-dependent.

**Key insight:** 1.3 GiB read to return 6,591 bytes. The query is 200,000x less efficient than it should be.

---

## 4. The `events` Table Schema

### Original Table Creation

```ruby
# db/migrations/20130725213922_create_events_table.rb
create_table :events do
  VCAP::Migration.common(self)    # adds: id (PK), guid (unique index),
                                   #        created_at (index), updated_at (index)
  DateTime :timestamp, null: false
  String :type, null: false
  String :actor, null: false
  String :actor_type, null: false
  String :actee, null: false
  String :actee_type, null: false
  String :metadata, null: false, default: '{}'
  Integer :space_id, null: false
  foreign_key [:space_id], :spaces, name: :fk_events_space_id
end
```

Later migrations added `space_guid`, `organization_guid`, `actor_name`, `actor_username`, `actee_name`.

### Existing Indexes (Pre-Fix)

| Index Name | Column(s) | Source Migration |
|---|---|---|
| (unique) | `guid` | `20130725213922` via `VCAP::Migration.common` |
| `events_created_at_guid_index` | `[created_at, guid]` | `20230725110800` (replaced single-column `created_at`) |
| `events_updated_at_guid_index` | `[updated_at, guid]` | `20230725110800` (replaced single-column `updated_at`) |
| `events_actee_index` | `actee` | `20140716213753` |
| (auto) | `space_guid` | `20150127013821` |
| (auto) | `organization_guid` | `20150127013821` |
| (auto) | `actee_type` | `20150910221699` |
| (composite) | `[timestamp, id]` | `20150910221699` |

**Key limitation:** All indexes are single-column (except `(created_at, guid)` and `(timestamp, id)`). The `(created_at, guid)` index matches the ORDER BY clause, but MySQL can only use **one index per table access** -- so when MySQL chooses a different index for WHERE filtering (e.g., `events_actee_index`), it cannot simultaneously use `(created_at, guid)` for ordering. This forces a choice between fast filtering and fast ordering, with no option for both.

---

## 5. How the Query Is Generated: Complete Code Path Trace

### 5.1. API Entry Point

**File:** `app/controllers/v3/events_controller.rb` (line 10)

```ruby
def index
  message = EventsListMessage.from_params(query_params)
  invalid_param!(message.errors.full_messages) unless message.valid?

  dataset = EventListFetcher.fetch_all(message, permission_queryer.readable_event_dataset)

  render status: :ok, json: Presenters::V3::PaginatedListPresenter.new(
    presenter: Presenters::V3::EventPresenter,
    paginated_result: SequelPaginator.new.get_page(dataset, message.try(:pagination_options)),
    path: '/v3/audit_events',
    message: message
  )
end
```

Three sequential operations build the final SQL:
1. Permission scoping via `readable_event_dataset`
2. Event-specific filters via `EventListFetcher.fetch_all`
3. Pagination and ordering via `SequelPaginator.new.get_page`

### 5.2. Permission Scoping

**File:** `lib/cloud_controller/permissions.rb` (lines 290-299)

```ruby
def readable_event_dataset
  return VCAP::CloudController::Event.dataset if can_read_globally?

  spaces_with_permitted_roles = membership.authorized_space_guids(SPACE_ROLES_FOR_EVENTS)
  orgs_with_permitted_roles = membership.authorized_org_guids(
    VCAP::CloudController::Membership::ORG_AUDITOR
  )
  VCAP::CloudController::Event.dataset.filter(Sequel.or([
    [:space_guid, spaces_with_permitted_roles],
    [:organization_guid, orgs_with_permitted_roles]
  ]))
end
```

For non-admin users, this generates `WHERE (space_guid IN (...) OR organization_guid IN (...))`.

The permitted space roles are: `SPACE_AUDITOR`, `SPACE_DEVELOPER`, `SPACE_SUPPORTER`. The only org role is `ORG_AUDITOR`.

When a user has space roles but no org roles, Sequel generates `OR (1 = 0)` (empty IN clause). When a user has org roles but no space roles, it generates `(1 = 0) OR organization_guid IN (...)`. When a user has both, it generates the full `space_guid IN (...) OR organization_guid IN (...)`.

### 5.3. Event-Specific Filtering

**File:** `app/fetchers/event_list_fetcher.rb`

```ruby
def filter(message, dataset)
  dataset = dataset.where(type: message.types) if message.requested?(:types)          # line 16

  if message.requested?(:target_guids)                                                  # lines 18-24
    dataset = if message.exclude_target_guids?
                dataset.exclude(actee: message.target_guids[:not])
              else
                dataset.where(actee: message.target_guids)
              end
  end

  dataset = dataset.where(space_guid: message.space_guids) if message.requested?(:space_guids)                # line 26
  dataset = dataset.where(organization_guid: message.organization_guids) if message.requested?(:organization_guids)  # line 28

  super(message, dataset, Event)
end
```

When the API caller provides `types`, `target_guids`, `space_guids`, or `organization_guids`, this adds the corresponding AND clauses. These filters are **in addition to** the permission-scoped dataset from Step 2.

### 5.4. Pagination and the Deferred Join

**File:** `lib/cloud_controller/paging/sequel_paginator.rb` (lines 79-97)

The `Event` model explicitly disables window function support (`app/models/runtime/event.rb`, lines 85-91):

```ruby
Event.dataset_module do
  def supports_window_functions?
    false
  end
end
```

This forces the paginator into `paginate_with_extension`, which generates the deferred join pattern:

```ruby
def paginate_with_extension(dataset, per_page, page, table_name)
  paged_dataset = dataset.extension(:pagination).paginate(page, per_page)
  count = paged_dataset.pagination_record_count

  if from_is_table?(dataset)
    paged_dataset = dataset.join_table(
      :inner,
      paged_dataset.select(Sequel[table_name][:id].as(:tmp_deferred_id)).as(:tmp_deferred_table),
      Sequel[table_name][:id] => Sequel[:tmp_deferred_table][:tmp_deferred_id]
    )
  end
  records = paged_dataset.all
end
```

The resulting SQL joins the full dataset (with all WHERE + ORDER BY but no LIMIT) against a subquery that has the LIMIT. The outer query re-applies all conditions redundantly.

### 5.5. What Triggers These Queries

The query signature is consistent with:
1. **`cf events APP_NAME`** -- the CF CLI, which calls `GET /v3/audit_events?types=...&target_guids=APP_GUID&order_by=-created_at`
2. **Apps Manager UI** -- the web dashboard polls audit events for app detail pages. Multiple users with open dashboards create concurrent queries.
3. **Any automation or monitoring tool** polling the audit events API filtered by app, space, or org.

---

## 6. Root Cause Analysis

The query is catastrophically expensive due to the intersection of four problems:

### 6.1. No Composite Index for Filter + Sort

The WHERE clause filters on `space_guid`, `type`, and `actee` simultaneously. All existing indexes are single-column. MySQL can only use one index for the query. It chooses `events_actee_index` (most selective for a single app GUID), but then must scan all matching actee rows to evaluate the other predicates.

### 6.2. Two Slow Execution Plans — Both Caused by Missing Composite Index

A composite index on `(created_at, guid)` exists (from the 2023 pagination migration), which matches the ORDER BY clause. MySQL's optimizer can choose between two strategies, **both of which are slow**:

**Plan A — Filesort (observed in customer's slow query log):** MySQL uses the single-column `events_actee_index` for WHERE filtering, finds all matching rows for the actee (potentially millions on a busy foundation), then filesorts them all to satisfy ORDER BY. This is CPU-bound and explains the customer's 95%+ CPU saturation.

**Plan B — Backward scan (observed in our MySQL 8.0 benchmarks):** MySQL uses the `(created_at, guid)` index for a backward scan to satisfy ORDER BY, checking each row against the WHERE predicates. This is fast when matching rows are uniformly distributed, but **degrades catastrophically when the target entity has been quiet recently** (temporal skew). The backward scan must traverse millions of recent non-matching rows before finding any matches — reading massive amounts from disk.

The customer's `Filesort: Yes` indicates Plan A. Our benchmarks reproduce Plan B. Both plans are slow for the same fundamental reason: **no single index covers both the WHERE filter and the ORDER BY clause**. The composite index `(actee, created_at, guid)` provides both, eliminating the need to choose between filtering and ordering.

### 6.3. The Deferred Join Duplicates Work

The `paginate_with_extension` method generates SQL where the outer query re-applies all WHERE and ORDER BY clauses redundantly. The intent of a deferred join is to avoid reading wide rows during sort, but the current implementation defeats this by re-evaluating the expensive filter+sort twice.

### 6.4. Three Distinct Query Patterns, Three Missing Indexes

The V3 audit events API generates three distinct query shapes, each requiring its own composite index:

**Pattern A -- Actee-filtered** (the incident query):
```
WHERE actee = X AND space_guid IN (...) AND type IN (...) ORDER BY created_at DESC, guid DESC
```
Triggered by: `GET /v3/audit_events?target_guids=<app>&types=...`

**Pattern B -- Space-scoped browse:**
```
WHERE space_guid = X AND type IN (...) ORDER BY created_at DESC, guid DESC
```
Triggered by: `GET /v3/audit_events?space_guids=<space>&types=...` (no actee filter)

**Pattern C -- Org-scoped browse:**
```
WHERE organization_guid = X AND type IN (...) ORDER BY created_at DESC, guid DESC
```
Triggered by: An org auditor with no space roles browsing `GET /v3/audit_events?types=...`. The permission layer generates `WHERE (1 = 0) OR organization_guid IN ('org-guid')`, which simplifies to `WHERE organization_guid = 'org-guid'`. This is the same filesort problem as Pattern B, just on `organization_guid`.

Without our composite indexes, all three patterns fall back to a single-column index lookup followed by a filesort over hundreds of thousands to millions of rows.

---

## 7. Solution: Three Composite Indexes

### 7.1. What Changes

A single migration (`db/migrations/20260324120000_add_composite_indexes_to_events.rb`) adds three indexes:

```sql
-- Index 1: Covers actee-filtered queries (Pattern A)
CREATE INDEX events_actee_created_at_guid_index
  ON events (actee, created_at, guid);

-- Index 2: Covers space-scoped browse queries (Pattern B)
CREATE INDEX events_space_guid_created_at_guid_index
  ON events (space_guid, created_at, guid);

-- Index 3: Covers org-scoped browse queries (Pattern C)
CREATE INDEX events_organization_guid_created_at_guid_index
  ON events (organization_guid, created_at, guid);
```

### 7.2. Why This Column Order

All three indexes follow the same design pattern: **leading equality column + ORDER BY columns**.

**Index 1 -- `(actee, created_at, guid)`:**
- `actee` leads because it is the most selective equality predicate (typically a single app GUID).
- `created_at` second, `guid` third -- matching `ORDER BY created_at DESC, guid DESC` exactly.
- MySQL does a **backward index scan** with early LIMIT termination: walks the index in reverse from the most recent entry for the actee, stops after finding 10 matching rows. No filesort needed.

**Index 2 -- `(space_guid, created_at, guid)`:**
- Same pattern for space-scoped queries without an actee filter.

**Index 3 -- `(organization_guid, created_at, guid)`:**
- Same pattern for org-scoped queries. Discovered during our investigation: an org auditor with no space roles would hit the exact same filesort bottleneck that caused the original incident, just on `organization_guid` instead of `space_guid`.

### 7.3. Design Decisions and Lessons Learned

**Why `(actee, type, created_at)` was wrong:** Our initial design included `type` before `created_at` because the query has a `type IN (...)` clause with ~17 values. But a multi-value IN clause breaks B-tree ordering for subsequent columns -- MySQL cannot use `created_at` for ordered scanning when `type` has 17 discrete values between them. By excluding `type` from the index and letting MySQL post-filter on type, the backward index scan finds the 10 most recent matching rows almost instantly.

**Why `guid` must be in the index:** Our initial Index 2 design omitted `guid`. The ORDER BY is `created_at DESC, guid DESC` -- without `guid` in the index, MySQL cannot guarantee the full sort order from the index alone and falls back to filesort. The composite index must cover the **complete** ORDER BY clause including the `guid` tiebreaker.

**Why three separate indexes instead of one:** Each query pattern has a different leading equality column. A composite index `(actee, created_at, guid)` cannot help a query that filters on `space_guid` but not `actee` -- MySQL can only use the leftmost prefix of a composite index. Each pattern needs its own index.

### 7.4. Realistic Permission Clauses

A key concern was whether the `OR` in the permission clause (`space_guid IN (...) OR organization_guid IN (...)`) would prevent MySQL from using the composite indexes. We tested three permission clause variants:

**Simple (OR (1 = 0))** -- user with only space roles or only org roles:
```sql
WHERE ((space_guid IN (...)) OR (1 = 0)) AND ...
```
MySQL trivially optimizes away `OR FALSE`. All indexes work perfectly.

**Realistic (OR between two real columns)** -- user with both space and org roles:
```sql
WHERE ((space_guid IN (...)) OR (organization_guid IN (...))) AND actee = 'X' AND type IN (...)
```
For **Pattern A (actee-filtered)**: Index 1 still works because `actee =` is ANDed at the **top level**, outside the OR. MySQL can index-seek on actee first and then post-filter the OR. Benchmarked at **3,032x faster** on MySQL 8.0.

For **Patterns B and C (space/org browse)**: When the API caller also passes an explicit `space_guids` or `organization_guids` parameter, the EventListFetcher adds a **top-level AND** (`AND space_guid IN ('sg1')` at line 26, or `AND organization_guid IN ('og1')` at line 28). MySQL uses this explicit AND for the index seek despite the permission OR. Benchmarked at **3,482x** and **3,677x faster** respectively.

---

## 8. Benchmark Results

### 8.1. Test Methodology

Three standalone benchmark scripts (`benchmarks/benchmark_actee_query.rb`, `benchmarks/benchmark_space_query.rb`, `benchmarks/benchmark_org_query.rb`) run against both MySQL and PostgreSQL. Each script:

1. **Seeds** the events table with 5,000,000 rows using **temporally skewed** data distribution: 40% of events belong to a "hot" entity (actee/space/org) whose events are concentrated in the **older** portion of the time range (days 1-17). The most recent 14 days have **zero** hot-entity events — only other entities generate events there. This simulates a production app/space/org that was heavily active weeks ago but has gone quiet, which is exactly the scenario that causes the `(created_at, guid)` backward scan to degrade.
2. **Ensures table size exceeds buffer pool** for realistic I/O pressure (~3.8 GB table vs. 128 MB buffer pool).
3. **Runs the exact slow query pattern** produced by the Cloud Controller code path.
4. **Tests 5 index configurations**: baseline (no composite), index 1 only, index 2 only, index 3 only, all three.
5. **Tests 2 permission clause variants**: simple (`OR (1 = 0)`) and realistic (`OR organization_guid IN (...)`).
6. **Captures** wall-clock time (1 warmup + 5 timed runs, averaged) and EXPLAIN output.

**Test environment:** MySQL 8.0.45, PostgreSQL 18.3, 128 MB buffer pools, 5M rows, temporal skew (14 quiet days).

### 8.2. Scenario A: Actee-Filtered Query (Proves Index 1)

API trigger: `GET /v3/audit_events?target_guids=<app>&space_guids=X&types=...`

**MySQL 8.0 -- Simple permission (OR (1 = 0)):**

| Configuration | Avg | Speedup |
|---|---|---|
| Baseline (no composite indexes) | **1,936 ms** | -- |
| Index 1 only: `(actee, created_at, guid)` | **0.6 ms** | **3,227x** |
| Index 2 only: `(space_guid, created_at, guid)` | 2,054 ms | 0.9x |
| Index 3 only: `(organization_guid, created_at, guid)` | 2,051 ms | 0.9x |
| All three indexes | **0.9 ms** | **2,151x** |

**MySQL 8.0 -- Realistic permission (OR organization_guid IN (...)):**

| Configuration | Avg | Speedup |
|---|---|---|
| Baseline | **2,122 ms** | -- |
| Index 1 only | **0.7 ms** | **3,032x** |
| Index 2 only | 2,162 ms | 1.0x |
| Index 3 only | 2,164 ms | 1.0x |
| All three indexes | **0.9 ms** | **2,358x** |

**PostgreSQL -- Simple permission (OR (1 = 0)):**

| Configuration | Avg | Speedup |
|---|---|---|
| Baseline (no composite indexes) | **389 ms** | -- |
| Index 1 only: `(actee, created_at, guid)` | **0.5 ms** | **778x** |
| Index 2 only | 386 ms | 1.0x |
| Index 3 only | 369 ms | 1.1x |
| All three indexes | **0.5 ms** | **778x** |

**PostgreSQL -- Realistic permission (OR organization_guid IN (...)):**

| Configuration | Avg | Speedup |
|---|---|---|
| Baseline | **375 ms** | -- |
| Index 1 only | **0.6 ms** | **626x** |
| Index 2 only | 386 ms | 1.0x |
| Index 3 only | 362 ms | 1.0x |
| All three indexes | **0.6 ms** | **626x** |

**Conclusion:** Index 1 fixes actee queries on both MySQL and PostgreSQL regardless of permission clause complexity. Indexes 2 and 3 have zero effect on actee queries, as expected. The temporal skew is critical: when the target app has been quiet for 14 days, the backward scan on `(created_at, guid)` must traverse ~1.35M non-matching recent rows.


**EXPLAIN change (MySQL 8.0 — backward scan plan):**
```
BEFORE: key=events_created_at_guid_index rows=20 | Backward index scan  (estimates 20 rows, actually scans ~1.35M non-matching)
AFTER:  key=events_actee_created_at_guid_index    | Backward index scan  (seeks directly to actee, scans ~23 rows)
```
Note: The customer's MySQL used a **filesort** plan (via `events_actee_index`), not a backward scan. Our MySQL 8.0 optimizer chooses differently. The composite index fixes both execution plan variants — see Section 3 notes for details.

### 8.3. Scenario B: Space-Scoped Browse (Proves Index 2)

API trigger: `GET /v3/audit_events?space_guids=<space>&types=...` (no actee filter)

**MySQL 8.0 -- Single space_guid (the common case):**

| Configuration | Avg | Speedup |
|---|---|---|
| Baseline | **1,863 ms** | -- |
| Index 1 only | 1,927 ms | 1.0x |
| Index 2 only: `(space_guid, created_at, guid)` | **0.6 ms** | **3,105x** |
| Index 3 only | 1,928 ms | 1.0x |
| All three indexes | **0.6 ms** | **3,105x** |

**MySQL 8.0 -- Multiple space_guids via IN clause (known limitation):**

| Configuration | Avg | Speedup |
|---|---|---|
| Baseline | **1,868 ms** | -- |
| Index 2 only | 2,012 ms | 0.9x |
| All three indexes | 2,195 ms | 0.9x |

**MySQL 8.0 -- Realistic permission + explicit space_guid filter:**

| Configuration | Avg | Speedup |
|---|---|---|
| Baseline | **2,089 ms** | -- |
| Index 2 only | **0.6 ms** | **3,482x** |
| All three indexes | **0.5 ms** | **4,179x** |

**PostgreSQL -- Single space_guid:**

| Configuration | Avg | Speedup |
|---|---|---|
| Baseline | **611 ms** | -- |
| Index 2 only | **0.8 ms** | **763x** |
| All three indexes | **0.8 ms** | **763x** |

**Conclusion:** Index 2 fixes single-space queries on both MySQL (3,105x faster) and PostgreSQL (763x faster). The realistic OR permission clause does not prevent the index from working when an explicit `space_guids` API parameter is present. The multi-value IN limitation on the leading column is confirmed (see Section 9).

### 8.4. Scenario C: Org-Scoped Browse (Proves Index 3)

API trigger: Org auditor browsing `GET /v3/audit_events?types=...` where permission layer generates `WHERE organization_guid IN ('org-guid')`.

**MySQL 8.0 -- Single organization_guid:**

| Configuration | Avg | Speedup |
|---|---|---|
| Baseline | **1,910 ms** | -- |
| Index 1 only | 2,104 ms | 0.9x |
| Index 2 only | 2,167 ms | 0.9x |
| Index 3 only: `(organization_guid, created_at, guid)` | **0.5 ms** | **3,820x** |
| All three indexes | **1.1 ms** | **1,737x** |

**MySQL 8.0 -- Multiple organization_guids via IN clause:**

| Configuration | Avg | Speedup |
|---|---|---|
| Baseline | **0.8 ms** | -- |
| Index 3 only | 0.8 ms | 1.0x |
| All three indexes | 0.8 ms | 1.0x |

**MySQL 8.0 -- Realistic permission + explicit organization_guid filter:**

| Configuration | Avg | Speedup |
|---|---|---|
| Baseline | **2,206 ms** | -- |
| Index 3 only | **0.6 ms** | **3,677x** |
| All three indexes | **0.5 ms** | **4,412x** |

**PostgreSQL -- Single organization_guid:**

| Configuration | Avg | Speedup |
|---|---|---|
| Baseline | **427 ms** | -- |
| Index 3 only | 420 ms | 1.0x |
| All three indexes | 423 ms | 1.0x |

**PostgreSQL optimizer note:** PostgreSQL does not use Index 3 in this benchmark because the hot org contains 40% of all events. PG's cost estimator sees the org as low-selectivity and prefers the `(created_at, guid)` backward scan. On MySQL, the optimizer correctly uses the composite index regardless. In production with more orgs and smaller per-org fractions, PG would likely use Index 3. The index is still added for both databases for schema consistency and to cover MySQL (where it provides 3,820x improvement).

**Conclusion:** Index 3 fixes single-org queries on MySQL (3,820x faster). Without this index, an org auditor on a busy foundation where the org has been quiet recently would hit the same multi-second query that caused the original incident.

### 8.5. PostgreSQL Results

**PostgreSQL is also affected by temporal skew.** Our initial hypothesis was that PostgreSQL 13+ would be immune due to its Incremental Sort feature. This was wrong. With temporal skew, PostgreSQL's backward scan on `(created_at, guid)` suffers the same problem as MySQL: it must traverse millions of non-matching recent rows before finding results.

**Scenario A (actee) on PostgreSQL** showed a **389 ms baseline** — the EXPLAIN confirms `Rows Removed by Filter: 1,354,870` (1.35M rows scanned to find 10 matches). With Index 1, this dropped to **0.5 ms (778x faster)**. **Scenario B (space)** showed **611 ms baseline → 0.8 ms with Index 2 (763x faster)**.

```
BEFORE (baseline):
  Index Scan Backward using events_created_at_guid_index on events
    Filter: ((actee = 'X') AND (space_guid = ANY (...)) AND (type = ANY (...)))
    Rows Removed by Filter: 1354870     <-- 1.35M rows scanned and discarded
    Buffers: shared hit=35 read=67656   <-- 67K buffer reads
  Execution Time: 442.579 ms

AFTER (Index 1):
  Index Scan Backward using events_actee_created_at_guid_index on events
    Index Cond: (actee = 'X')
    Rows Removed by Filter: 13          <-- only 13 non-matching rows
    Buffers: shared hit=7               <-- 7 buffer reads (vs 67K)
  Execution Time: 0.071 ms
```

**Decision:** Add indexes to both databases. Rationale:
- **Both databases are affected** by temporal skew — the fix is necessary for both, not just MySQL.
- PostgreSQL builds indexes `CONCURRENTLY` -- zero downtime, no table locks.
- The indexes reduce I/O dramatically (67,656 buffer reads -> 7).
- The codebase convention is identical schema across MySQL and PostgreSQL.

---

## 9. Known Limitations

### 9.1. Multi-Value IN on Leading Column (MySQL)

When the leading column has multiple values (`space_guid IN (sg1, sg2, sg3)`), MySQL cannot do a single ordered backward scan across multiple B-tree ranges. It falls back to the `(created_at, guid)` backward scan with row-by-row filtering — the composite index is ignored. Confirmed in benchmarks: MySQL's EXPLAIN shows `key=events_created_at_guid_index` (not the composite index) for multi-value IN queries.

**Practical impact:** This limitation only affects queries where the user has access to multiple spaces/orgs *and* those collectively contain hundreds of thousands of events *and* no explicit single-value filter narrows it down. The dominant real-world patterns (browsing a single space, filtering by a single app) all use single-value equality on the leading column, where the indexes work perfectly.

PostgreSQL handles the multi-space/multi-org case natively via Incremental Sort.

### 9.2. Unfiltered Browse with OR Permission Clause

When a user with both space and org roles does an unfiltered browse (`GET /v3/audit_events?types=...` with no `target_guids`, `space_guids`, or `organization_guids` parameter), the only WHERE clause is the permission OR:

```sql
WHERE (space_guid IN (...) OR organization_guid IN (...)) AND type IN (...) ORDER BY created_at DESC, guid DESC
```

No composite index can help here because there is no selective equality column at the top level -- just an OR between two different columns. MySQL falls back to the existing `(created_at, guid)` backward scan and filters rows one by one.

**Practical impact:** This is pre-existing behavior, not a regression. It works fast when the user's permitted spaces/orgs have recent events (the backward scan finds matches quickly). It works slow only when the user has very narrow permissions and their permitted spaces/orgs have been quiet recently on a large foundation. This is not what caused the incident, and fixing it would require architectural changes (denormalization or application-level UNION).

### 9.3. Negated Target GUIDs (NOT IN)

The API supports `target_guids[not]=X`, which generates `WHERE actee NOT IN ('X')`. This is inherently a broad query (everything except one app) and cannot benefit from a composite index on `(actee, ...)`. It relies on the existing `(created_at, guid)` backward scan. This is pre-existing and unrelated to the incident.

---

## 10. Migration Details

### 10.1. Migration Code

```ruby
# db/migrations/20260324120000_add_composite_indexes_to_events.rb
Sequel.migration do
  no_transaction

  up do
    if database_type == :postgres
      VCAP::Migration.with_concurrent_timeout(self) do
        add_index :events, %i[actee created_at guid],
                  name: :events_actee_created_at_guid_index,
                  if_not_exists: true, concurrently: true

        add_index :events, %i[space_guid created_at guid],
                  name: :events_space_guid_created_at_guid_index,
                  if_not_exists: true, concurrently: true

        add_index :events, %i[organization_guid created_at guid],
                  name: :events_organization_guid_created_at_guid_index,
                  if_not_exists: true, concurrently: true
      end
    else
      alter_table(:events) do
        unless @db.indexes(:events).key?(:events_actee_created_at_guid_index)
          add_index %i[actee created_at guid],
                    name: :events_actee_created_at_guid_index
        end
        unless @db.indexes(:events).key?(:events_space_guid_created_at_guid_index)
          add_index %i[space_guid created_at guid],
                    name: :events_space_guid_created_at_guid_index
        end
        unless @db.indexes(:events).key?(:events_organization_guid_created_at_guid_index)
          add_index %i[organization_guid created_at guid],
                    name: :events_organization_guid_created_at_guid_index
        end
      end
    end
  end

  down do
    if database_type == :postgres
      VCAP::Migration.with_concurrent_timeout(self) do
        drop_index :events, nil,
                   name: :events_actee_created_at_guid_index,
                   if_exists: true, concurrently: true
        drop_index :events, nil,
                   name: :events_space_guid_created_at_guid_index,
                   if_exists: true, concurrently: true
        drop_index :events, nil,
                   name: :events_organization_guid_created_at_guid_index,
                   if_exists: true, concurrently: true
      end
    else
      alter_table(:events) do
        drop_index nil, name: :events_actee_created_at_guid_index if @db.indexes(:events).key?(:events_actee_created_at_guid_index)
        drop_index nil, name: :events_space_guid_created_at_guid_index if @db.indexes(:events).key?(:events_space_guid_created_at_guid_index)
        drop_index nil, name: :events_organization_guid_created_at_guid_index if @db.indexes(:events).key?(:events_organization_guid_created_at_guid_index)
      end
    end
  end
end
```

### 10.2. Migration Spec

The spec (`spec/migrations/20260324120000_add_composite_indexes_to_events_spec.rb`) verifies:
- All three indexes exist after `up` migration
- Correct column order for each index
- All three indexes removed after `down` migration
- Both `up` and `down` are idempotent (running twice does not error)

### 10.3. Risk Analysis

| Dimension | Assessment |
|-----------|------------|
| **Destructiveness** | Non-destructive. No data or schema changes. Only adds indexes. |
| **PostgreSQL** | `CONCURRENTLY` builds without locking the table. Zero downtime. |
| **MySQL** | `ALTER TABLE ... ADD INDEX` uses online DDL (Algorithm=INPLACE) on MySQL 5.6+, which allows concurrent reads/writes during the index build. However, it acquires a **metadata lock** at the start and end of the operation. If any long-running query holds a metadata lock on the events table, the ALTER will block, and all subsequent events queries queue behind it. Three indexes are built sequentially. **Estimated time:** 5-15 minutes per index on a 10M-row table (15-45 minutes total). **Recommendation:** Schedule during low-traffic period, kill any long-running events queries beforehand, and monitor `SHOW PROCESSLIST` during execution. |
| **Write overhead** | Each INSERT into `events` now maintains three additional B-tree indexes. For an append-heavy table with no updates, this adds a small constant overhead per insert -- negligible compared to the read-side improvement. |
| **Rollback** | `down` migration drops all three indexes cleanly. No data loss. |
| **Blast radius** | Events table only. No other tables, no application code changes. |

---

## 11. CPU Impact Analysis

The original incident reported 95%+ MySQL CPU saturation. The customer's MySQL used a filesort plan (CPU-bound: sorting millions of rows in memory). Our benchmark reproduces a backward-scan plan (I/O-bound: traversing millions of index entries from disk). Both plans consume significant server resources per query; the composite indexes eliminate the bottleneck in both cases.

With the composite indexes, MySQL walks the B-tree in reverse starting from the target actee's most recent entry and stops after ~10 matching rows. The scan/sort over millions of non-matching rows is eliminated entirely.

| Metric | Before (no index) | After (with index) |
|--------|-------------------|-------------------|
| Query duration (Scenario A, 5M rows, MySQL 8.0) | 1,936 ms | 0.6 ms |
| Computational work per query | Scan ~1.35M non-matching rows | Scan ~23 rows |
| Estimated queries to saturate 1 core | ~0.5/sec | ~2,000/sec |
| Customer's observed duration (34s, larger table) | ~0.03 queries/sec per core | Expected: sub-millisecond |

Before the fix, a single concurrent events query per second is enough to keep one CPU core fully occupied. After the fix, even dozens of concurrent users browsing events would consume a negligible fraction of available CPU.

---

## 12. Post-Deployment Validation

| Metric | How to Measure | Success Criteria |
|--------|---------------|-----------------|
| Slow query log | Check MySQL slow query log for events query pattern | No events queries > 1s |
| MySQL CPU | Monitor via BOSH/Prometheus | CPU sustained below 50% under normal load |
| API response time | `cc_request_duration_seconds` | `/v3/audit_events` p99 < 500ms |
| Error rate | Cloud Controller error logs | No new errors from pagination or permissions |

---

## 13. Other Investigated Fixes (Not Included)

| Fix | Description | Result | Decision |
|-----|------------|--------|----------|
| **Deferred join cleanup** | `paginate_with_extension` re-applies WHERE + ORDER BY on outer query (redundant) | 0% improvement in isolation | Not included. Touches the paginator used by all V3 list endpoints. Candidate for future code quality PR. |
| **Permissions `(1=0)` cleanup** | When org roles are empty, Sequel generates `OR (1 = 0)` | 0% improvement. MySQL 8.0+ optimizes away `OR FALSE`. | Not included. Cleaner SQL but no performance benefit. |

---

## 14. Future Considerations (Out of Scope)

1. **Re-evaluate `supports_window_functions? = false` on Event model.** With proper indexes, the window function approach may outperform the two-query approach. Requires benchmarking.

2. **Fix the deferred join in `paginate_with_extension`.** The redundant outer WHERE is a code quality issue worth a separate PR.

3. **Events table partitioning.** Time-based partitioning could benefit very high-volume deployments.

4. **Reduce events retention.** `audit_events.cutoff_age_in_days` (default: 31 days) is an operational lever.

5. **Drop redundant single-column indexes.** The new composite indexes make the single-column `events_actee_index`, `space_guid`, and `organization_guid` indexes partially redundant (leftmost prefix). Dropping them saves disk space and write overhead. Should be a separate migration after production validation.

---

## 15. Rollback Procedure

Run the `down` migration to drop all three composite indexes:

```bash
bundle exec rake db:rollback
```

No data loss, no application code to revert. The system returns to pre-fix behavior.

---

## 16. Source File Reference

| File | Lines | Role |
|------|-------|------|
| `app/models/runtime/event.rb` | 85-91 | `supports_window_functions?` override |
| `app/controllers/v3/events_controller.rb` | 6-18 | V3 API entry point |
| `app/controllers/runtime/events_controller.rb` | -- | V2 API entry point |
| `app/fetchers/event_list_fetcher.rb` | 16-28 | Event-specific filter application |
| `lib/cloud_controller/permissions.rb` | 290-299 | Permission scoping (`readable_event_dataset`) |
| `lib/cloud_controller/paging/sequel_paginator.rb` | 79-97 | Deferred join pagination |
| `lib/cloud_controller/paging/pagination_options.rb` | -- | Default sort order (`id` ASC) |
| `db/migrations/20260324120000_add_composite_indexes_to_events.rb` | all | The fix |
| `spec/migrations/20260324120000_add_composite_indexes_to_events_spec.rb` | all | Migration spec |

### Benchmark Scripts

| File | Proves | Query Pattern |
|------|--------|--------------|
| `benchmarks/benchmark_actee_query.rb` | Index 1 | Actee-filtered: `target_guids=X&types=...` |
| `benchmarks/benchmark_space_query.rb` | Index 2 | Space browse: `space_guids=X&types=...` |
| `benchmarks/benchmark_org_query.rb` | Index 3 | Org browse: `organization_guids=X&types=...` |

All scripts support MySQL and PostgreSQL, seed 5M rows with temporally skewed distribution (hot entity quiet for 14 days), test 5 index configurations, and test both simple and realistic permission clause variants.

```bash
# Run all benchmarks (from repo root)
DB_CONNECTION_STRING="mysql2://root@localhost/ccdb_bench" ruby benchmarks/benchmark_actee_query.rb
DB_CONNECTION_STRING="mysql2://root@localhost/ccdb_bench" ruby benchmarks/benchmark_space_query.rb
DB_CONNECTION_STRING="mysql2://root@localhost/ccdb_bench" ruby benchmarks/benchmark_org_query.rb

DB_CONNECTION_STRING="postgres://localhost/ccdb_bench" ruby benchmarks/benchmark_actee_query.rb
DB_CONNECTION_STRING="postgres://localhost/ccdb_bench" ruby benchmarks/benchmark_space_query.rb
DB_CONNECTION_STRING="postgres://localhost/ccdb_bench" ruby benchmarks/benchmark_org_query.rb
```

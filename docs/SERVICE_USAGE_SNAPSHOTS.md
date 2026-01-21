# Service Usage Snapshots Feature

## Overview

Service usage snapshots provide a point-in-time baseline of all service instances (both managed and user-provided) with a checkpoint in the service usage event stream. This feature mirrors the app usage snapshots functionality and enables non-destructive baseline establishment for service billing systems.

## Problem Statement

### The Current Problem with `destructively_purge_all_and_reseed`

Similar to app usage events, service usage events face the same onboarding challenge: when a new billing consumer wants to start tracking service usage events, the CREATE events for currently existing service instances have often been pruned (30-day retention). Without these CREATE events, the billing system cannot establish a baseline.

**The current "solution" is destructive:**

1. Admin calls `POST /v3/service_usage_events/actions/destructively_purge_all_and_reseed`
2. System **TRUNCATES** the entire `service_usage_events` table (deletes ALL events)
3. System creates synthetic "CREATE" events for all currently existing service instances
4. New billing system starts consuming from event ID 1

**This breaks existing consumers:**

- Billing System A has been tracking since day 1 with perfect accuracy
- Billing System B joins and needs a baseline
- Admin runs `purge_and_reseed`
- **Billing System A's event stream is now corrupted** - all checkpoint IDs are invalid, processed events are gone
- Historical audit trail is destroyed for everyone

### The Solution: Service Usage Snapshots

Service usage snapshots provide a **non-destructive** alternative that:

1. **Captures a point-in-time baseline** of all service instances (managed and user-provided)
2. **Ties the snapshot to a checkpoint** in the event stream (`max(service_usage_event.id)`)
3. **Preserves the event stream** for all existing consumers
4. **Enables multiple independent consumers** without coordination

**Key benefits:**

- Existing consumers unaffected
- Event history preserved
- Multiple consumers can onboard independently
- Handles both managed and user-provided service instances
- No race conditions (transactional guarantees)
- Follows established V3 async job pattern

## Data Model

Each snapshot consists of:

1. **Parent Snapshot Record** - Contains summary totals and checkpoint reference
2. **Space Detail Records** - One record per space with service instances, containing embedded JSON with per-instance details

```
┌─────────────────────────────────┐
│ ServiceUsageSnapshot (parent)   │
├─────────────────────────────────┤
│ id, guid                        │
│ checkpoint_event_id             │
│ checkpoint_event_created_at     │
│ created_at, completed_at        │
│ service_instance_count (total)  │
│ organization_count              │
│ space_count                     │
└─────────────────────────────────┘
            │ 1:N
            ▼
┌─────────────────────────────────┐
│ ServiceUsageSnapshotSpace       │
├─────────────────────────────────┤
│ id                              │
│ service_usage_snapshot_id (FK)  │
│ space_guid                      │
│ organization_guid               │
│ service_instance_count          │
│ service_instances (JSON)        │
│   [{"guid":"...",               │
│     "name":"my-db",             │
│     "type":"managed",           │
│     "service_label":"mysql",    │
│     "plan_name":"small"}, ...]  │
└─────────────────────────────────┘
```

## Consumer Onboarding Workflow

### Step 1: Request a Snapshot

```bash
curl "https://api.example.org/v3/service_usage/snapshots" \
  -X POST \
  -H "Authorization: bearer [token]"
```

**Response:**
```http
HTTP/1.1 202 Accepted
Location: /v3/jobs/abc123-def456-ghi789
```

### Step 2: Poll for Job Completion

```bash
curl "https://api.example.org/v3/jobs/abc123-def456-ghi789" \
  -H "Authorization: bearer [token]"
```

**Response (Processing):**
```json
{
  "guid": "abc123-def456-ghi789",
  "state": "PROCESSING",
  "operation": "service_usage_snapshot.generate",
  "links": {
    "self": { "href": "/v3/jobs/abc123-def456-ghi789" }
  }
}
```

**Response (Complete):**
```json
{
  "guid": "abc123-def456-ghi789",
  "state": "COMPLETE",
  "operation": "service_usage_snapshot.generate",
  "links": {
    "self": { "href": "/v3/jobs/abc123-def456-ghi789" },
    "service_usage_snapshot": { "href": "/v3/service_usage/snapshots/snapshot-guid-123" }
  }
}
```

### Step 3: Retrieve the Snapshot Summary

```bash
curl "https://api.example.org/v3/service_usage/snapshots/snapshot-guid-123" \
  -H "Authorization: bearer [token]"
```

**Response:**
```json
{
  "guid": "snapshot-guid-123",
  "created_at": "2026-01-14T10:00:00Z",
  "completed_at": "2026-01-14T10:00:05Z",
  "checkpoint_event_id": 98765,
  "checkpoint_event_created_at": "2026-01-14T09:59:59Z",
  "summary": {
    "service_instance_count": 1500,
    "organization_count": 50,
    "space_count": 200
  },
  "links": {
    "self": { "href": "/v3/service_usage/snapshots/snapshot-guid-123" },
    "checkpoint_event": { "href": "/v3/service_usage_events/98765" },
    "spaces": { "href": "/v3/service_usage/snapshots/snapshot-guid-123/spaces" }
  }
}
```

### Step 4: Retrieve Per-Space Details (Optional)

For detailed per-space and per-instance data:

```bash
curl "https://api.example.org/v3/service_usage/snapshots/snapshot-guid-123/spaces" \
  -H "Authorization: bearer [token]"
```

**Response:**
```json
{
  "pagination": {
    "total_results": 200,
    "total_pages": 4,
    "first": { "href": "/v3/service_usage/snapshots/snapshot-guid-123/spaces?page=1" },
    "last": { "href": "/v3/service_usage/snapshots/snapshot-guid-123/spaces?page=4" },
    "next": { "href": "/v3/service_usage/snapshots/snapshot-guid-123/spaces?page=2" },
    "previous": null
  },
  "resources": [
    {
      "space_guid": "space-abc-123",
      "organization_guid": "org-xyz-789",
      "service_instance_count": 5,
      "service_instances": [
        { "guid": "si-1", "name": "my-db", "type": "managed", "service_label": "mysql", "plan_name": "small" },
        { "guid": "si-2", "name": "my-cache", "type": "managed", "service_label": "redis", "plan_name": "medium" },
        { "guid": "si-3", "name": "my-creds", "type": "user_provided", "service_label": null, "plan_name": null }
      ]
    },
    {
      "space_guid": "space-def-456",
      "organization_guid": "org-xyz-789",
      "service_instance_count": 2,
      "service_instances": [
        { "guid": "si-4", "name": "other-db", "type": "managed", "service_label": "postgres", "plan_name": "large" },
        { "guid": "si-5", "name": "other-cache", "type": "managed", "service_label": "redis", "plan_name": "small" }
      ]
    }
  ]
}
```

### Step 5: Start Consuming Events

```bash
curl "https://api.example.org/v3/service_usage_events?after_guid=event-at-checkpoint-98765" \
  -H "Authorization: bearer [token]"
```

**Your billing system now has:**

- **Baseline**: The `checkpoint_event_id` marks the point at which the snapshot was taken
- **Summary counts**: `service_instance_count`, `organization_count`, `space_count` for the baseline
- **Per-space details**: Breakdown of service instances by space with full metadata
- **Stream**: All events after checkpoint 98765
- **Completeness**: No gaps, no duplicates

## API Endpoints

### POST /v3/service_usage/snapshots

**Request:**
```bash
curl "https://api.example.org/v3/service_usage/snapshots" \
  -X POST \
  -H "Authorization: bearer [token]"
```

**Response:**
```http
HTTP/1.1 202 Accepted
Location: /v3/jobs/abc123-def456-ghi789
```

**Error Cases:**

- `409 Conflict`: Another snapshot is already being generated
- `403 Forbidden`: Requires global admin permissions

### GET /v3/service_usage/snapshots/:guid

**Request:**
```bash
curl "https://api.example.org/v3/service_usage/snapshots/snapshot-guid-123" \
  -H "Authorization: bearer [token]"
```

**Response:** See Step 3 above

### GET /v3/service_usage/snapshots

**Request:**
```bash
curl "https://api.example.org/v3/service_usage/snapshots?per_page=50" \
  -H "Authorization: bearer [token]"
```

**Response:**
```json
{
  "pagination": { ... },
  "resources": [
    {
      "guid": "snapshot-guid-123",
      "created_at": "2026-01-14T10:00:00Z",
      "completed_at": "2026-01-14T10:00:05Z",
      "checkpoint_event_id": 98765,
      "summary": { ... },
      "links": { ... }
    }
  ]
}
```

### GET /v3/service_usage/snapshots/:guid/spaces

Retrieve per-space detail records for a completed snapshot.

**Query Parameters:**
- `per_page` (optional): Number of results per page (default: 50)
- `page` (optional): Page number

**Required Permission:** Global read access

**Response:** Paginated list of space records with embedded service instance details

**Error:**
- `422 Unprocessable Entity` if snapshot is still processing

## Architecture

### Database Schema

**service_usage_snapshots table:**
- `id`: Primary key
- `guid`: Unique identifier
- `checkpoint_event_id`: Last service_usage_event.id at snapshot time
- `checkpoint_event_created_at`: Timestamp of checkpoint event
- `created_at`: Snapshot creation start time
- `completed_at`: Snapshot completion time (NULL = in progress)
- `service_instance_count`: Total service instances in snapshot
- `organization_count`: Unique organizations
- `space_count`: Unique spaces

**service_usage_snapshot_spaces table:**
- `id`: Primary key
- `service_usage_snapshot_id`: Foreign key to parent snapshot (CASCADE DELETE)
- `space_guid`: Space identifier
- `organization_guid`: Organization identifier
- `service_instance_count`: Count of instances in this space
- `service_instances`: JSON array of instance details

### Snapshot Generation Process

1. **Create Placeholder**: Create snapshot record with `completed_at = NULL`
2. **Checkpoint**: Record `max(service_usage_event.id)` and its `created_at`
3. **Query**: Fetch all service instances grouped by space
4. **Batch Insert**: Create space records with embedded JSON (1000 per batch)
5. **Mark Complete**: Set `completed_at` timestamp and summary counts

**Note on Concurrent Requests:** In rare cases (two admins clicking simultaneously), two snapshots may be created with the same `checkpoint_event_id`. This is harmless - both contain valid data, and consumers can dedupe by checkpoint if needed.

### Performance Characteristics

**Estimated Generation Times:**

| Service Instances | Spaces | Estimated Time |
|-------------------|--------|----------------|
| 1,000 | 100 | < 1 second |
| 10,000 | 1,000 | 1-2 seconds |
| 100,000 | 10,000 | 10-30 seconds |
| 1,000,000 | 100,000 | 2-5 minutes |

**Factors affecting performance:**
- Database load
- Number of LEFT JOINs (deleted entities)
- Mix of managed vs user-provided instances
- Index health

## Checkpoint Validation

The `checkpoint_event_created_at` field enables drift detection:

```bash
# Check if checkpoint event still exists
curl "https://api.example.org/v3/service_usage_events/98765" \
  -H "Authorization: bearer [token]"
```

**If 404**: Checkpoint event was pruned (>30 days old). Create a new snapshot and reconcile your state with the new baseline.

**If 200**: Verify `created_at` matches `checkpoint_event_created_at` from snapshot

**Tip:** Create snapshots more frequently than the 30-day pruning window to ensure you always have a valid checkpoint to fall back to.

## Edge Cases

### Deleted Organizations or Spaces

If an organization or space is deleted while a service instance still exists, the snapshot will still account for that instance in the summary counts. The LEFT JOINs used in the query handle this gracefully.

## Cleanup and Retention

**Automatic Cleanup:**
- Runs daily at 04:05 UTC
- Deletes completed snapshots older than 31 days (configurable)
- Only deletes snapshots where `completed_at IS NOT NULL`
- FK CASCADE automatically deletes associated space records

**Configuration:**
```yaml
service_usage_snapshot:
  cutoff_age_in_days: 31
```

## Deprecation Path

With service usage snapshots available, the destructive `POST /v3/service_usage_events/actions/destructively_purge_all_and_reseed` endpoint should be:

1. **Documented as deprecated** (immediate)
2. **Logged with warnings** when used (next release)
3. **Removed** (after 2-3 releases, with migration guide)

**Migration Guide for Consumers:**

Instead of:
```bash
# OLD (destructive)
curl "https://api.example.org/v3/service_usage_events/actions/destructively_purge_all_and_reseed" \
  -X POST \
  -H "Authorization: bearer [token]"
```

Use:
```bash
# NEW (non-destructive)
curl "https://api.example.org/v3/service_usage/snapshots" \
  -X POST \
  -H "Authorization: bearer [token]"
```

## Monitoring and Observability

**Prometheus Metrics:**

- `cc_service_usage_snapshot_generation_duration_seconds` (histogram): Generation time
- `cc_service_usage_snapshot_service_instance_count` (gauge): Service instances in last snapshot
- `cc_service_usage_snapshot_generation_failures_total` (counter): Failed generations
- `cc_service_usage_snapshot_cleaned_up_total` (gauge): Snapshots deleted by cleanup job

**Logs:**

- `cc.service_usage_snapshot_repository`: Snapshot generation
- `cc.background.service-usage-snapshot-generator`: Job execution
- `cc.background.service-usage-snapshot-cleanup`: Cleanup job

## Design Decisions

This section documents intentional design choices made during implementation.

### Stale Snapshot Cleanup Timeout (1 Hour)

The cleanup job considers snapshots "stale" if they've been processing for more than 1 hour without completing. This timeout was chosen because:
- Normal snapshot generation completes within minutes, even for very large foundations
- 1 hour provides ample buffer for slow systems or database contention
- It's short enough to not block new snapshot requests indefinitely
- It aligns with similar timeout patterns elsewhere in the codebase

### Checkpoint Event May Be Pruned

The `checkpoint_event_id` stored in a snapshot may point to an event that has since been pruned (events are pruned after 30 days by default). This is intentional:
- The checkpoint represents a point-in-time reference, not a guarantee the event still exists
- Billing consumers should create new snapshots before their checkpoint events are pruned
- The `checkpoint_event_created_at` timestamp provides an additional reference point for validation

**Recommendation:** Create snapshots more frequently than the pruning window (e.g., weekly) to ensure you always have a valid checkpoint.

### Per-Space Detail Records with Embedded JSON

The snapshot stores per-space detail records with embedded JSON containing service instance data. This design choice balances:
- **Detail**: Full per-instance breakdown (guid, name, type, service_label, plan_name)
- **Efficiency**: One row per space instead of one row per instance
- **Queryability**: Space-level aggregates are directly accessible
- **Flexibility**: JSON allows for future schema evolution without migrations

### Pagination Limits

The snapshot list endpoint uses the standard Cloud Controller pagination via `SequelPaginator`. The default and maximum page sizes are enforced by the paginator, consistent with all other V3 list endpoints. This ensures:
- Consistent behavior across all APIs
- Protection against unbounded queries
- Predictable memory usage

## Related Documentation

- [App Usage Snapshots](APP_USAGE_SNAPSHOTS.md): Parallel feature for app usage events
- [Service Usage Events API](https://v3-apidocs.cloudfoundry.org/version/3.x.x/index.html#service-usage-events): Event stream API

## Implementation Notes

This feature mirrors the app usage snapshots implementation with key adaptations:

- Queries `ServiceInstance` instead of `ProcessModel`
- No state filtering (all service instances are "active")
- Handles both managed and user-provided service instances
- Separate error codes (440004-440006 vs 440001-440003)
- Separate cleanup schedule (04:05 vs 04:00)

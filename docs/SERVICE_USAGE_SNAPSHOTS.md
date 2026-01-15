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
5. **Provides full auditability** with per-service-instance details

**Key benefits:**

- Existing consumers unaffected
- Event history preserved
- Multiple consumers can onboard independently
- Full audit trail for billing disputes
- Handles both managed and user-provided service instances
- No race conditions (transactional guarantees)
- Follows established V3 async job pattern

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

### Step 3: Retrieve the Snapshot

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
    "details": { "href": "/v3/service_usage/snapshots/snapshot-guid-123/details" },
    "job": { "href": "/v3/jobs/abc123-def456-ghi789" },
    "checkpoint_event": { "href": "/v3/service_usage_events/98765" }
  }
}
```

### Step 4: Consume the Baseline

```bash
curl "https://api.example.org/v3/service_usage/snapshots/snapshot-guid-123/details?per_page=5000" \
  -H "Authorization: bearer [token]"
```

**Response:**
```json
{
  "pagination": {
    "total_results": 1500,
    "total_pages": 1,
    "first": { "href": "/v3/service_usage/snapshots/snapshot-guid-123/details?page=1&per_page=5000" },
    "last": { "href": "/v3/service_usage/snapshots/snapshot-guid-123/details?page=1&per_page=5000" },
    "next": null,
    "previous": null
  },
  "resources": [
    {
      "organization_guid": "org-123",
      "space_guid": "space-456",
      "service_instance_guid": "si-789",
      "service_instance_name": "my-database",
      "service_instance_type": "managed_service_instance",
      "service_plan_guid": "plan-abc",
      "service_plan_name": "standard",
      "service_offering_guid": "service-def",
      "service_offering_name": "postgresql",
      "service_broker_guid": "broker-ghi",
      "service_broker_name": "aws-broker"
    },
    {
      "organization_guid": "org-123",
      "space_guid": "space-456",
      "service_instance_guid": "si-999",
      "service_instance_name": "my-user-provided-service",
      "service_instance_type": "user_provided",
      "service_plan_guid": null,
      "service_plan_name": null,
      "service_offering_guid": null,
      "service_offering_name": null,
      "service_broker_guid": null,
      "service_broker_name": null
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

- **Baseline**: All service instances that existed at checkpoint 98765
- **Stream**: All events after checkpoint 98765
- **Completeness**: No gaps, no duplicates

## Service Instance Types

Service usage snapshots handle two types of service instances:

### Managed Service Instances

Provisioned through service brokers with plans:

```json
{
  "service_instance_guid": "si-789",
  "service_instance_name": "my-database",
  "service_instance_type": "managed_service_instance",
  "service_plan_guid": "plan-abc",
  "service_plan_name": "standard",
  "service_offering_guid": "service-def",
  "service_offering_name": "postgresql",
  "service_broker_guid": "broker-ghi",
  "service_broker_name": "aws-broker"
}
```

### User-Provided Service Instances

Created directly by users without brokers:

```json
{
  "service_instance_guid": "si-999",
  "service_instance_name": "my-external-api",
  "service_instance_type": "user_provided",
  "service_plan_guid": null,
  "service_plan_name": null,
  "service_offering_guid": null,
  "service_offering_name": null,
  "service_broker_guid": null,
  "service_broker_name": null
}
```

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

### GET /v3/service_usage/snapshots/:guid/details

**Request:**
```bash
curl "https://api.example.org/v3/service_usage/snapshots/snapshot-guid-123/details?organization_guids=org-123&per_page=100" \
  -H "Authorization: bearer [token]"
```

**Query Parameters:**
- `organization_guids`: Filter by organization GUID(s)
- `space_guids`: Filter by space GUID(s)
- `service_instance_guids`: Filter by service instance GUID(s)
- `service_plan_guids`: Filter by service plan GUID(s)
- `service_offering_guids`: Filter by service offering GUID(s)
- `service_broker_guids`: Filter by service broker GUID(s)
- `per_page`: Results per page (default: 50, max: 5000)
- `page`: Page number

**Response:** See Step 4 above

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

**service_usage_snapshot_details table:**
- `id`: Primary key
- `snapshot_id`: Foreign key to service_usage_snapshots
- `organization_guid`: Denormalized org GUID
- `space_guid`: Denormalized space GUID
- `service_instance_guid`: Service instance GUID
- `service_instance_name`: Service instance name
- `service_instance_type`: 'managed_service_instance' or 'user_provided'
- `service_plan_guid`: Plan GUID (NULL for user-provided)
- `service_plan_name`: Plan name (NULL for user-provided)
- `service_offering_guid`: Service GUID (NULL for user-provided)
- `service_offering_name`: Service label (NULL for user-provided)
- `service_broker_guid`: Broker GUID (NULL for user-provided)
- `service_broker_name`: Broker name (NULL for user-provided)

### Snapshot Generation Process

1. **Create Placeholder**: Create snapshot record with `completed_at = NULL`
2. **Checkpoint**: Record `max(service_usage_event.id)` and its `created_at`
3. **Query**: Fetch all service instances with LEFT JOINs for deleted orgs/spaces and user-provided services
4. **Transactional Insert**: Batch insert details (1000 rows at a time)
5. **Mark Complete**: Set `completed_at` timestamp

**Note on Concurrent Requests:** In rare cases (two admins clicking simultaneously), two snapshots may be created with the same `checkpoint_event_id`. This is harmless - both contain valid data, and consumers can dedupe by checkpoint if needed.

**Query Pattern:**
```sql
SELECT
  organizations.guid AS organization_guid,
  spaces.guid AS space_guid,
  service_instances.guid AS service_instance_guid,
  service_instances.name AS service_instance_name,
  CASE
    WHEN service_instances.is_gateway_service = false THEN 'user_provided'
    ELSE 'managed_service_instance'
  END AS service_instance_type,
  service_plans.guid AS service_plan_guid,
  service_plans.name AS service_plan_name,
  services.guid AS service_offering_guid,
  services.label AS service_offering_name,
  service_brokers.guid AS service_broker_guid,
  service_brokers.name AS service_broker_name
FROM service_instances
LEFT JOIN spaces ON spaces.id = service_instances.space_id
LEFT JOIN organizations ON organizations.id = spaces.organization_id
LEFT JOIN service_plans ON service_plans.id = service_instances.service_plan_id
LEFT JOIN services ON services.id = service_plans.service_id
LEFT JOIN service_brokers ON service_brokers.id = services.service_broker_id
ORDER BY service_instances.id
```

### Performance Characteristics

**Estimated Generation Times:**

| Service Instances | Estimated Time | Notes |
|-------------------|----------------|-------|
| 1,000 | < 1 second | Typical small foundation |
| 10,000 | 1-2 seconds | Medium foundation |
| 100,000 | 10-30 seconds | Large foundation |
| 1,000,000 | 2-5 minutes | Very large foundation |

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

If an organization or space is deleted while a service instance still exists, the snapshot will still capture that instance. The `organization_guid` and `space_guid` fields may be NULL in this case. This is intentional - billing systems should still account for orphaned service instances.

### Verifying Snapshot Integrity

Each snapshot provides an `integrity_valid?` check that verifies:
1. The snapshot has completed (not stuck in processing)
2. The number of detail records matches the expected count

Billing consumers should verify integrity before trusting snapshot data. See the App Usage Snapshots documentation for detailed usage examples.

## Cleanup and Retention

**Automatic Cleanup:**
- Runs daily at 04:05 UTC
- Deletes completed snapshots older than 31 days (configurable)
- Only deletes snapshots where `completed_at IS NOT NULL`

**Configuration:**
```yaml
service_usage_snapshots:
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
- `cc_service_usage_snapshots_cleaned_up_total` (gauge): Snapshots deleted by cleanup job

**Logs:**

- `cc.service_usage_snapshot_repository`: Snapshot generation
- `cc.background.service-usage-snapshot-generator`: Job execution
- `cc.background.service-usage-snapshots-cleanup`: Cleanup job

## Related Documentation

- [App Usage Snapshots](USAGE_SNAPSHOTS.md): Parallel feature for app usage events
- [Service Usage Events API](https://v3-apidocs.cloudfoundry.org/version/3.x.x/index.html#service-usage-events): Event stream API

## Implementation Notes

This feature mirrors the app usage snapshots implementation with key adaptations:

- Queries `ServiceInstance` instead of `ProcessModel`
- No state filtering (all service instances are "active")
- Handles both managed and user-provided service instances
- Uses `Sequel.case` for `service_instance_type` determination
- Service-specific fields (plan, offering, broker) are nullable
- Separate error codes (390004-390006 vs 390001-390003)
- Separate cleanup schedule (04:05 vs 04:00)

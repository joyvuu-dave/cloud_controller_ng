# App Usage Snapshots Feature

## Overview

Usage snapshots provide a point-in-time baseline of running apps and services with a checkpoint in the event stream. This feature eliminates the need for the destructive `destructively_purge_all_and_reseed` operation and enables multiple independent billing consumers.

## Problem Statement

### The Current Problem with `destructively_purge_all_and_reseed`

Cloud Foundry's `destructively_purge_all_and_reseed` endpoint was designed to solve a critical onboarding problem for billing systems: when a new billing consumer wants to start tracking usage events, the START events for currently running apps have often been pruned (30-day retention). Without these START events, the billing system cannot establish a baseline.

**The current "solution" is destructive:**

1. Admin calls `POST /v3/app_usage_events/actions/destructively_purge_all_and_reseed`
2. System **TRUNCATES** the entire `app_usage_events` table (deletes ALL events)
3. System creates synthetic "START" events for all currently running apps
4. New billing system starts consuming from event ID 1

**This breaks existing consumers:**

- Billing System A has been tracking since day 1 with perfect accuracy
- Billing System B joins and needs a baseline
- Admin runs `purge_and_reseed`
- **Billing System A's event stream is now corrupted** - all checkpoint IDs are invalid, processed events are gone
- Historical audit trail is destroyed for everyone

### The Solution: App Usage Snapshots

Usage snapshots provide a **non-destructive** alternative that:

1. **Captures a point-in-time baseline** of all running apps/services
2. **Ties the snapshot to a checkpoint** in the event stream (`max(app_usage_event.id)`)
3. **Preserves the event stream** for all existing consumers
4. **Enables multiple independent consumers** without coordination
5. **Provides full auditability** with per-app/process details

**Key benefits:**

- Existing consumers unaffected
- Event history preserved
- Multiple consumers can onboard independently
- Full audit trail for billing disputes
- No race conditions (transactional guarantees)
- Follows established V3 async job pattern

## Consumer Onboarding Workflow

### Step 1: Request a Snapshot

```bash
curl "https://api.example.org/v3/app_usage/snapshots" \
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
  "operation": "usage_snapshot.generate",
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
  "operation": "usage_snapshot.generate",
  "links": {
    "self": { "href": "/v3/jobs/abc123-def456-ghi789" },
    "usage_snapshot": { "href": "/v3/app_usage/snapshots/snapshot-guid-123" }
  }
}
```

### Step 3: Retrieve the Snapshot

```bash
curl "https://api.example.org/v3/app_usage/snapshots/snapshot-guid-123" \
  -H "Authorization: bearer [token]"
```

**Response:**
```json
{
  "guid": "snapshot-guid-123",
  "created_at": "2026-01-14T10:00:00Z",
  "completed_at": "2026-01-14T10:00:15Z",
  "checkpoint_event_id": 999999,
  "summary": {
    "process_count": 15234,
    "organization_count": 42,
    "space_count": 156
  },
  "links": {
    "self": { "href": "/v3/app_usage/snapshots/snapshot-guid-123" },
    "details": { "href": "/v3/app_usage/snapshots/snapshot-guid-123/details" },
    "checkpoint_event": { "href": "/v3/app_usage_events/999999" }
  }
}
```

### Step 4: Retrieve Snapshot Details (Paginated)

```bash
curl "https://api.example.org/v3/app_usage/snapshots/snapshot-guid-123/details?per_page=100" \
  -H "Authorization: bearer [token]"
```

**Response:**
```json
{
  "pagination": {
    "total_results": 15234,
    "total_pages": 153,
    "first": { "href": "/v3/app_usage/snapshots/snapshot-guid-123/details?page=1&per_page=100" },
    "last": { "href": "/v3/app_usage/snapshots/snapshot-guid-123/details?page=153&per_page=100" },
    "next": { "href": "/v3/app_usage/snapshots/snapshot-guid-123/details?page=2&per_page=100" }
  },
  "resources": [
    {
      "organization_guid": "org-a",
      "space_guid": "space-x",
      "app_guid": "app-1",
      "process_guid": "proc-1",
      "process_type": "web",
      "instances": 5
    },
    ...
  ]
}
```

### Step 5: Start Processing Events from Checkpoint

```bash
curl "https://api.example.org/v3/app_usage_events?after_guid=999999&per_page=100" \
  -H "Authorization: bearer [token]"
```

Your billing system now has:
- **Baseline**: All currently running apps from the snapshot
- **Event stream**: All events after the checkpoint

## API Reference

### POST /v3/app_usage/snapshots

Create a new usage snapshot (async operation).

**Required Permission:** Global read access

**Response:**
- `202 Accepted` with `Location` header pointing to the job

### GET /v3/app_usage/snapshots

List all app usage snapshots.

**Query Parameters:**
- `created_after` (optional): ISO 8601 timestamp
- `created_before` (optional): ISO 8601 timestamp
- `per_page` (optional): Number of results per page
- `page` (optional): Page number

**Required Permission:** Global read access

### GET /v3/app_usage/snapshots/:guid

Retrieve a specific snapshot.

**Required Permission:** Global read access

**Response:** Snapshot object with summary counts and links

### GET /v3/app_usage/snapshots/:guid/details

Retrieve paginated snapshot details.

**Query Parameters:**
- `organization_guids[]` (optional): Filter by organization GUIDs
- `space_guids[]` (optional): Filter by space GUIDs
- `per_page` (optional): Number of results per page
- `page` (optional): Page number

**Required Permission:** Global read access

## Checkpoint Validation and Drift Detection

### Validating Checkpoint Existence

To verify if a checkpoint is still valid (not pruned), use the existing app usage events endpoint:

```bash
curl "https://api.example.org/v3/app_usage_events/999999" \
  -H "Authorization: bearer [token]"
```

- **200 OK**: Checkpoint is valid
- **404 Not Found**: Checkpoint has been pruned, request a new snapshot

### Detecting Drift

Each snapshot includes `checkpoint_event_created_at` timestamp, which records when the checkpoint event was created. This enables drift detection:

```json
{
  "guid": "snapshot-guid-123",
  "checkpoint_event_id": 999999,
  "checkpoint_event_created_at": "2026-01-14T10:00:00Z",
  "created_at": "2026-01-14T10:00:15Z",
  ...
}
```

If the checkpoint event is pruned, you can compare `checkpoint_event_created_at` with your last processed event timestamp to determine if you've missed events and need to reconcile your state with a new snapshot.

## Example Billing System Integration

```ruby
class UsageTracker
  def initialize(api_client)
    @api_client = api_client
  end

  def start_tracking
    # Request a snapshot
    job_response = @api_client.post('/v3/app_usage/snapshots')
    job_guid = job_response['guid']

    # Poll for completion
    snapshot_guid = wait_for_job_completion(job_guid)

    # Get snapshot summary
    snapshot = @api_client.get("/v3/app_usage/snapshots/#{snapshot_guid}")
    checkpoint = snapshot['checkpoint_event_id']

    # Load baseline from snapshot details
    load_baseline(snapshot_guid)

    # Start processing events from checkpoint
    process_events_from(checkpoint)
  end

  private

  def wait_for_job_completion(job_guid)
    loop do
      job = @api_client.get("/v3/jobs/#{job_guid}")
      
      case job['state']
      when 'COMPLETE'
        return extract_snapshot_guid(job['links']['usage_snapshot']['href'])
      when 'FAILED'
        raise "Snapshot generation failed"
      when 'PROCESSING'
        sleep 5
      end
    end
  end

  def load_baseline(snapshot_guid)
    page = 1
    loop do
      response = @api_client.get("/v3/app_usage/snapshots/#{snapshot_guid}/details?page=#{page}&per_page=1000")
      
      response['resources'].each do |detail|
        store_baseline(
          org: detail['organization_guid'],
          space: detail['space_guid'],
          app: detail['app_guid'],
          process: detail['process_guid'],
          type: detail['process_type'],
          instances: detail['instances']
        )
      end

      break unless response['pagination']['next']
      page += 1
    end
  end

  def process_events_from(checkpoint)
    after_guid = checkpoint
    loop do
      events = @api_client.get("/v3/app_usage_events?after_guid=#{after_guid}&per_page=100")
      
      events['resources'].each do |event|
        process_event(event)
        after_guid = event['guid']
      end

      # Continue polling for new events
      sleep 60 if events['resources'].empty?
    end
  end
end
```

## Edge Cases and Error Handling

### Concurrent Snapshot Generation

If a snapshot is already being generated, subsequent requests will fail with:

```json
{
  "errors": [{
    "code": 390001,
    "title": "CF-AppUsageSnapshotGenerationInProgress",
    "detail": "An app usage snapshot is already being generated. Please wait for it to complete."
  }]
}
```

**Solution**: Wait for the current snapshot to complete or use the existing in-progress snapshot.

### Duplicate Checkpoints

In rare cases (two admins clicking simultaneously), two snapshots may be created with the same `checkpoint_event_id`. This is harmless because:

- Both snapshots contain valid, consistent data
- The checkpoint is just a "starting point" marker
- Consumers should dedupe by `checkpoint_event_id` if needed

The race window is extremely small (milliseconds), and the cost of adding database-level locking to prevent this is not justified.

### Snapshot Generation Failure

If snapshot generation fails, the job will show:

```json
{
  "guid": "abc123-def456-ghi789",
  "state": "FAILED",
  "errors": [...]
}
```

**Solution**: Retry the snapshot creation. The system ensures no partial snapshots are created. Any stale in-progress snapshots (stuck for more than 1 hour) are automatically cleaned up.

### Deleted Organizations or Spaces

If an organization or space is deleted while a process is still running, the snapshot will still capture that process. The `organization_guid` and `space_guid` fields may be NULL in this case. This is intentional - billing systems should still account for orphaned processes.

### Large Datasets

For foundations with 100K+ running processes:
- Snapshot generation may take 30-60 seconds
- Details endpoint is paginated (use `per_page` and `page` parameters)
- Consider filtering by `organization_guids` or `space_guids` if you only need specific data

### Checkpoint Pruning

Usage events are pruned after 30 days. If your snapshot's `checkpoint_event` link returns 404, the checkpoint event has been pruned.

**How to handle this:**

1. Check if the checkpoint event exists:
   ```bash
   curl "https://api.example.org/v3/app_usage_events/999999" \
     -H "Authorization: bearer [token]"
   ```

2. If you receive a 404, create a new snapshot:
   ```bash
   curl "https://api.example.org/v3/app_usage/snapshots" \
     -X POST \
     -H "Authorization: bearer [token]"
   ```

3. Reconcile your state with the new baseline and resume processing from the new checkpoint.

**Tip:** Create snapshots more frequently than the 30-day pruning window to ensure you always have a valid checkpoint to fall back to.

### Verifying Snapshot Integrity

Each snapshot provides an `integrity_valid?` check that verifies:
1. The snapshot has completed (not stuck in processing)
2. The number of detail records matches the expected count

Billing consumers should verify integrity before trusting snapshot data:

```ruby
snapshot = fetch_snapshot(guid)

if snapshot.processing?
  # Still generating, wait and retry
  sleep(30)
  retry
elsif !snapshot.integrity_valid?
  # Something went wrong, request a new snapshot
  log.error("Snapshot #{guid} failed integrity check")
  request_new_snapshot
else
  # Safe to use for billing
  process_snapshot_for_billing(snapshot)
end
```

**What integrity_valid? catches:**
- Partial failures where some batches inserted but not all
- Snapshots stuck in processing state
- Any mismatch between expected and actual detail count

**What it doesn't catch:**
- Logical errors in the query (wrong processes selected)
- Data corruption within individual records

## Performance Characteristics

**Expected snapshot generation times:**

| Running Processes | Generation Time |
|-------------------|-----------------|
| 1,000             | 100-300ms       |
| 10,000            | 1-3 seconds     |
| 100,000           | 10-30 seconds   |
| 1,000,000         | 2-5 minutes     |

Note: These are estimates for typical hardware. Actual times depend on database performance, disk I/O, and system load. The snapshot generation uses LEFT JOINs and batch inserts to minimize database load.

**Storage requirements:**

- Snapshot record: ~100 bytes
- Detail record: ~200 bytes per process
- 100K processes: ~20MB per snapshot
- With 31-day retention: ~620MB for daily snapshots

## Future Enhancements

### Phase 2: Service Usage Events

Once app app usage snapshots are stable, the feature will be extended to service instances:

- Query `ServiceInstance` table for existing instances
- Create `service_app_usage_snapshots` and `service_app_usage_snapshot_details` tables
- Reuse same API pattern and job infrastructure
- Combined endpoint: `GET /v3/app_usage/snapshots?types=app,service`

## Migration from `destructively_purge_all_and_reseed`

### Before (Old Method)

```bash
# This destroys ALL events for ALL consumers
curl "https://api.example.org/v3/app_usage_events/actions/destructively_purge_all_and_reseed" \
  -X POST \
  -H "Authorization: bearer [token]"
```

### After (New Method)

```bash
# This creates a snapshot without affecting any consumers
curl "https://api.example.org/v3/app_usage/snapshots" \
  -X POST \
  -H "Authorization: bearer [token]"
```

**Deprecation Notice:** The `destructively_purge_all_and_reseed` endpoint is now deprecated. Please use app usage snapshots instead. The old endpoint will be removed in a future major version.

## Support

For issues or questions:
- GitHub Issues: [cloud_controller_ng/issues](https://github.com/cloudfoundry/cloud_controller_ng/issues)
- Cloud Foundry Slack: #capi channel
- Documentation: [Cloud Foundry Docs](https://docs.cloudfoundry.org)

# App Usage Snapshots Feature

## Overview

Usage snapshots provide a point-in-time baseline of running apps with a checkpoint in the event stream. This feature eliminates the need for the destructive `destructively_purge_all_and_reseed` operation and enables multiple independent billing consumers.

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

**Key benefits:**

- Existing consumers unaffected
- Event history preserved
- Multiple consumers can onboard independently
- No race conditions (transactional guarantees)
- Follows established V3 async job pattern
- **Scales to very large datasets** via chunked storage

## Data Model

Each snapshot consists of:

1. **Parent Snapshot Record** - Contains summary totals and checkpoint reference
2. **Chunk Records** - Each chunk contains up to 100 processes for a single space

```
┌─────────────────────────────┐
│ AppUsageSnapshot (parent)   │
├─────────────────────────────┤
│ id, guid                    │
│ checkpoint_event_id         │
│ checkpoint_event_created_at │
│ created_at, completed_at    │
│ instance_count (total)      │
│ process_count (total)       │
│ organization_count          │
│ space_count                 │
│ chunk_count                 │
│ last_processed_process_id   │  ← For resumability
└─────────────────────────────┘
            │ 1:N
            ▼
┌─────────────────────────────┐
│ AppUsageSnapshotChunk       │
├─────────────────────────────┤
│ id                          │
│ app_usage_snapshot_id (FK)  │
│ organization_guid           │
│ space_guid                  │
│ chunk_index (0, 1, 2...)    │  ← For spaces with many processes
│ process_count               │
│ instance_count              │
│ processes (JSON)            │
│   [{"app_guid":"...",       │
│     "process_type":"web",   │
│     "instances":3}, ...]    │
└─────────────────────────────┘
```

### Chunking Strategy

Each chunk contains up to **100 processes** for a **single space**. If a space has more than 100 processes, it gets multiple chunks:

- **Space with 50 processes** → 1 chunk (chunk_index: 0)
- **Space with 250 processes** → 3 chunks (chunk_index: 0, 1, 2)
- **10,000 spaces with 1 process each** → 10,000 chunks

This ensures:
- **Bounded memory usage** during generation (streaming, not all-in-memory)
- **Bounded API response sizes** (each chunk is small)
- **Resumability** for crash recovery (last_processed_process_id)

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
  "operation": "app_usage_snapshot.generate",
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
  "operation": "app_usage_snapshot.generate",
  "links": {
    "self": { "href": "/v3/jobs/abc123-def456-ghi789" },
    "usage_snapshot": { "href": "/v3/app_usage/snapshots/snapshot-guid-123" }
  }
}
```

### Step 3: Retrieve the Snapshot Summary

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
  "checkpoint_event_created_at": "2026-01-14T09:59:58Z",
  "summary": {
    "instance_count": 15234,
    "process_count": 5000,
    "organization_count": 42,
    "space_count": 156,
    "chunk_count": 200
  },
  "links": {
    "self": { "href": "/v3/app_usage/snapshots/snapshot-guid-123" },
    "checkpoint_event": { "href": "/v3/app_usage_events/999999" },
    "chunks": { "href": "/v3/app_usage/snapshots/snapshot-guid-123/chunks" }
  }
}
```

### Step 4: Retrieve Chunks (Optional)

For detailed per-process data, paginate through chunks:

```bash
curl "https://api.example.org/v3/app_usage/snapshots/snapshot-guid-123/chunks" \
  -H "Authorization: bearer [token]"
```

**Response:**
```json
{
  "pagination": {
    "total_results": 200,
    "total_pages": 4,
    "first": { "href": "/v3/app_usage/snapshots/snapshot-guid-123/chunks?page=1" },
    "last": { "href": "/v3/app_usage/snapshots/snapshot-guid-123/chunks?page=4" },
    "next": { "href": "/v3/app_usage/snapshots/snapshot-guid-123/chunks?page=2" },
    "previous": null
  },
  "resources": [
    {
      "organization_guid": "org-xyz-789",
      "space_guid": "space-abc-123",
      "chunk_index": 0,
      "process_count": 100,
      "instance_count": 350,
      "processes": [
        { "app_guid": "app-1", "process_type": "web", "instances": 100 },
        { "app_guid": "app-1", "process_type": "worker", "instances": 25 },
        { "app_guid": "app-2", "process_type": "web", "instances": 25 }
      ]
    },
    {
      "organization_guid": "org-xyz-789",
      "space_guid": "space-abc-123",
      "chunk_index": 1,
      "process_count": 50,
      "instance_count": 150,
      "processes": [
        { "app_guid": "app-3", "process_type": "web", "instances": 150 }
      ]
    }
  ]
}
```

### Step 5: Start Processing Events from Checkpoint

```bash
curl "https://api.example.org/v3/app_usage_events?after_guid=999999&per_page=100" \
  -H "Authorization: bearer [token]"
```

Your billing system now has:
- **Baseline**: The `checkpoint_event_id` marks the point at which the snapshot was taken
- **Summary counts**: `instance_count`, `process_count`, `organization_count`, `space_count` for the baseline
- **Per-process details**: Breakdown of instances by space and process (via chunks)
- **Event stream**: All events after the checkpoint

## API Reference

### POST /v3/app_usage/snapshots

Create a new usage snapshot (async operation).

**Required Permission:** Global write access

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

### GET /v3/app_usage/snapshots/:guid/chunks

Retrieve chunk records for a completed snapshot.

**Query Parameters:**
- `per_page` (optional): Number of results per page (default: 50)
- `page` (optional): Page number

**Required Permission:** Global read access

**Response:** Paginated list of chunk records with embedded process details

**Error:**
- `422 Unprocessable Entity` if snapshot is still processing

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

    # Record baseline counts (summary level)
    record_baseline(
      instance_count: snapshot['summary']['instance_count'],
      process_count: snapshot['summary']['process_count'],
      org_count: snapshot['summary']['organization_count'],
      space_count: snapshot['summary']['space_count'],
      checkpoint: checkpoint
    )

    # Optionally, record per-process details for detailed tracking
    record_chunk_details(snapshot_guid)

    # Start processing events from checkpoint
    process_events_from(checkpoint)
  end

  private

  def record_chunk_details(snapshot_guid)
    page = 1
    loop do
      response = @api_client.get("/v3/app_usage/snapshots/#{snapshot_guid}/chunks?page=#{page}")
      
      response['resources'].each do |chunk|
        record_chunk_baseline(
          space_guid: chunk['space_guid'],
          org_guid: chunk['organization_guid'],
          chunk_index: chunk['chunk_index'],
          process_count: chunk['process_count'],
          instance_count: chunk['instance_count'],
          processes: chunk['processes']
        )
      end
      
      break if response['pagination']['next'].nil?
      page += 1
    end
  end

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
    "code": 440001,
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

### Resumability

If snapshot generation is interrupted (server restart, etc.), the system tracks `last_processed_process_id` to allow resumption. This ensures very large snapshots can be generated even if the process needs to be restarted.

### Deleted Organizations or Spaces

If an organization or space is deleted while a process is still running, the snapshot will still account for that process in the summary counts. The LEFT JOINs used in the query handle this gracefully.

### Large Datasets

For foundations with millions of running instances:
- Snapshot generation uses **streaming** (paged_each) to avoid loading all data into memory
- Chunks are **batch-inserted** (1000 records per batch) for efficiency
- Each chunk contains at most **100 processes** to keep response sizes bounded
- Generation may take hours or days for extremely large datasets, but remains **non-blocking**

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

## Performance Characteristics

**Expected snapshot generation times:**

| Running Processes | Spaces  | Chunks   | Generation Time |
|-------------------|---------|----------|-----------------|
| 1,000             | 100     | 100      | 100-300ms       |
| 10,000            | 1,000   | 1,000    | 1-3 seconds     |
| 100,000           | 10,000  | 10,000   | 10-30 seconds   |
| 1,000,000         | 100,000 | 100,000+ | 2-5 minutes     |

Note: These are estimates for typical hardware. Actual times depend on database performance, disk I/O, and system load.

**Scale characteristics:**
- Memory usage: **Bounded** regardless of data size (streaming + chunking)
- Database load: **Non-blocking** (uses keyset pagination, no table locks)
- API responses: **Bounded** (each chunk ≤ 100 processes)

**Storage requirements:**
- Snapshot record: ~100 bytes per snapshot
- Chunk record: ~500 bytes + JSON size per chunk (~50 processes average)
- With 31-day retention and 10K chunks: ~5MB per snapshot

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

## Design Decisions

This section documents intentional design choices made during implementation.

### Simple Fixed-Size Chunking

The snapshot uses a simple chunking strategy: each chunk = up to 100 processes for one space. We considered adaptive chunking (different chunk types for different hierarchies) but rejected it because:

- Same storage requirements with either approach
- Simple chunking is much easier to understand and debug
- Consumer code is simpler (one chunk format to parse)
- At extreme scale, most chunks would be process-level anyway

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

### Chunked Storage for Scale

The snapshot stores data in bounded chunks (max 100 processes per chunk) rather than one record per space. This design choice enables:
- **Bounded memory** during generation (streaming, not all-in-memory)
- **Bounded API responses** (each page is small)
- **Resumability** (can continue after crash)
- **Arbitrarily large scale** (even trillions of processes, theoretically)

### Instance Count vs Process Count

The `instance_count` field represents the **total number of running instances** across all processes, not the number of processes. This is the correct metric for billing purposes because:
- A single process can have multiple instances (e.g., 3 instances of a web process)
- Billing is typically based on instance-hours, not process-hours
- The instance count reflects actual resource consumption

The `process_count` field is also provided for completeness.

## Support

For issues or questions:
- GitHub Issues: [cloud_controller_ng/issues](https://github.com/cloudfoundry/cloud_controller_ng/issues)
- Cloud Foundry Slack: #capi channel
- Documentation: [Cloud Foundry Docs](https://docs.cloudfoundry.org)

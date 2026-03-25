#!/usr/bin/env ruby
# rubocop:disable Rails/SquishedSQLHeredocs
# benchmark_org_query.rb
#
# PROVES: Index 3 -- (organization_guid, created_at, guid) fixes the org-scoped browse query.
#
# This benchmark reproduces the query pattern where an org auditor browses audit
# events for their organization WITHOUT filtering by a specific app (actee) or
# space. This is the "what happened in my org recently?" view.
#
# With the existing (created_at, guid) index, MySQL attempts a backward scan to
# satisfy ORDER BY. When the target org has been quiet recently (temporal skew),
# MySQL must scan through millions of recent non-matching rows before finding
# matches for the target org -- causing multi-second queries. With
# (organization_guid, created_at, guid), MySQL seeks directly to the org's rows.
#
# This is the EXACT SAME pattern as Scenario B (space browse), just with
# organization_guid instead of space_guid. We discovered this gap during the
# TNZ-89706 fix: an org auditor with no space roles would hit the same multi-second
# query that caused the original incident.
#
# CODE PATH THAT TRIGGERS THIS QUERY:
#   API call: GET /v3/audit_events?organization_guids=<org_guid>&types=audit.app.start,...
#             (no target_guids / actee filter, no space_guids filter)
#
#   1. app/controllers/v3/events_controller.rb#index (line 10)
#        dataset = EventListFetcher.fetch_all(message, permission_queryer.readable_event_dataset)
#
#   2. app/fetchers/event_list_fetcher.rb#fetch_all
#        Line 16: dataset = dataset.where(type: message.types)
#        Line 28: dataset = dataset.where(organization_guid: message.organization_guids)
#        NO actee filter, NO space_guid filter applied.
#
#   3. lib/cloud_controller/permissions.rb#readable_event_dataset (lines 290-299)
#        For org auditor with NO space roles:
#        Generates: WHERE (1 = 0) OR organization_guid IN ('org-1-guid')
#        Which MySQL simplifies to: WHERE organization_guid IN ('org-1-guid')
#
#   4. lib/cloud_controller/paging/sequel_paginator.rb#paginate_with_extension (lines 79-97)
#        Event model disables window functions (app/models/runtime/event.rb:85-91),
#        forcing the deferred join path.
#
# RESULTING SQL — simple permission (the query we benchmark):
#   SELECT * FROM events
#   INNER JOIN (
#       SELECT events.id AS tmp_deferred_id FROM events
#       WHERE (((1 = 0) OR (organization_guid IN (...)))
#         AND (type IN (...)))
#       ORDER BY events.created_at DESC, events.guid DESC
#       LIMIT 10 OFFSET 0
#   ) AS tmp_deferred_table ON (events.id = tmp_deferred_table.tmp_deferred_id)
#   WHERE (((1 = 0) OR (organization_guid IN (...)))
#     AND (type IN (...)))
#   ORDER BY events.created_at DESC, events.guid DESC
#
# REALISTIC PERMISSION VARIANT (user with both org auditor and space roles):
#   ...WHERE ((space_guid IN (...)) OR (organization_guid IN (...)))
#     AND organization_guid IN ('org-1-guid')    -- explicit filter from API param
#     AND (type IN (...))
#   When an explicit organization_guids param is also passed, the EventListFetcher
#   adds a top-level AND organization_guid IN (...) (line 28). MySQL may use this
#   explicit AND for the index seek, even though the permission OR remains.
#
# EXPECTED RESULTS (with temporal skew -- hot org quiet for last 14 days):
#   - BASELINE:    Slow (multi-second on MySQL). Backward scan on (created_at, guid)
#                  must traverse recent non-matching rows.
#   - INDEX 1:     Still slow. Index 1 is for actee queries; irrelevant here.
#   - INDEX 2:     Still slow. Index 2 is for space queries; irrelevant here.
#   - INDEX 3:     Fast (~1 ms). Seeks directly to org's rows via composite index.
#   - ALL THREE:   Fast (~1 ms). Index 3 handles this query; Indexes 1 and 2 are unused.
#
# NOTE: PostgreSQL 13+ handles this efficiently at baseline via Incremental Sort.
# See benchmark_actee_query.rb header for details.
#
# RUN:
#   DB_CONNECTION_STRING="mysql2://root@localhost/ccdb_bench" ruby benchmarks/benchmark_org_query.rb
#   DB_CONNECTION_STRING="postgres://localhost/ccdb_bench" ruby benchmarks/benchmark_org_query.rb
#
# Requirements: gem install sequel mysql2  (or: gem install sequel pg)

require 'sequel'
require 'securerandom'
require 'benchmark'

# --- Configuration ---
ROW_COUNT       = Integer(ENV.fetch('ROW_COUNT', 5_000_000))
WARMUP_RUNS     = Integer(ENV.fetch('WARMUP_RUNS', 1))
BENCHMARK_RUNS  = Integer(ENV.fetch('BENCHMARK_RUNS', 5))

HOT_ACTEE_FRACTION  = Float(ENV.fetch('HOT_ACTEE_FRACTION', '0.40'))
NUM_OTHER_ACTEES    = Integer(ENV.fetch('NUM_OTHER_ACTEES', 5_000))
NUM_SPACES          = Integer(ENV.fetch('NUM_SPACES', 200))
HOT_ACTEE_SPACES    = Integer(ENV.fetch('HOT_ACTEE_SPACES', 5))
NUM_ORGS            = Integer(ENV.fetch('NUM_ORGS', 50))
# TEMPORAL SKEW: The hot org is COMPLETELY quiet during the most recent
# QUIET_DAYS -- zero events of any kind. Hot actee events are concentrated in
# the older ACTIVE_DAYS period, and during the quiet period, other actees'
# events are routed ONLY to non-hot orgs. This simulates a production org
# that has been fully idle (e.g., a team decommissioned or on holiday).
# The backward scan on (created_at, guid) must traverse ALL recent non-matching
# rows before finding any events in the hot org.
TOTAL_DAYS  = Integer(ENV.fetch('TOTAL_DAYS', 31))
QUIET_DAYS  = Integer(ENV.fetch('QUIET_DAYS', 14))
ACTIVE_DAYS = TOTAL_DAYS - QUIET_DAYS

EVENT_TYPES = %w[
  app.crash audit.app.create audit.app.deployment.create audit.app.deployment.cancel
  audit.app.map-route audit.app.process.crash audit.app.process.create
  audit.app.process.scale audit.app.process.terminate_instance audit.app.process.update
  audit.app.restage audit.app.start audit.app.stop audit.app.unmap-route
  audit.app.update audit.app.ssh-authorized audit.app.ssh-unauthorized
  audit.organization.create audit.space.create audit.service_instance.create
  audit.route.create audit.service_binding.create
].freeze

QUERY_TYPES = EVENT_TYPES[0..16]

DB_URL = ENV.fetch('DB_CONNECTION_STRING', 'mysql2://root@localhost/ccdb_bench')
DB = Sequel.connect(DB_URL)

IS_POSTGRES = DB.database_type == :postgres
IS_MYSQL    = !IS_POSTGRES

# --- Index Definitions ---
INDEX_1 = { name: :events_actee_created_at_guid_index, cols: %i[actee created_at guid] }.freeze
INDEX_2 = { name: :events_space_guid_created_at_guid_index, cols: %i[space_guid created_at guid] }.freeze
INDEX_3 = { name: :events_organization_guid_created_at_guid_index, cols: %i[organization_guid created_at guid] }.freeze
ALL_INDEXES = [INDEX_1, INDEX_2, INDEX_3].freeze

# --- Database Helpers ---
def qi(id) = IS_POSTGRES ? "\"#{id}\"" : "`#{id}`"

def analyze_table
  IS_POSTGRES ? DB.run('ANALYZE events') : DB.fetch('ANALYZE TABLE events').all
end

def db_version
  v = DB.fetch('SELECT version() as v').first[:v]
  IS_POSTGRES ? v.split[0..1].join(' ') : v
end

def buffer_info
  if IS_POSTGRES
    raw = DB.fetch('SHOW shared_buffers').first[:shared_buffers]
    bytes = case raw
            when /(\d+)\s*GB/i then Regexp.last_match(1).to_i * 1024 * 1024 * 1024
            when /(\d+)\s*MB/i then Regexp.last_match(1).to_i * 1024 * 1024
            when /(\d+)\s*kB/i then Regexp.last_match(1).to_i * 1024
            else raw.to_i * 8192
            end
    { bytes: bytes, label: 'shared_buffers' }
  else
    raw = DB.fetch("SHOW VARIABLES LIKE 'innodb_buffer_pool_size'").first[:Value].to_i
    { bytes: raw, label: 'innodb_buffer_pool_size' }
  end
end

def table_size_bytes
  if IS_POSTGRES
    DB.fetch("SELECT pg_total_relation_size('events') AS s").first[:s]
  else
    DB.fetch("SELECT (data_length + index_length) AS s FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'events'").first[:s]
  end
end

# --- Schema Setup ---
def setup_schema
  DB.drop_table?(:events)
  DB.create_table(:events) do
    primary_key :id, type: :Bignum
    String   :guid,              null: false, size: 255
    DateTime :created_at,        null: false
    DateTime :updated_at
    DateTime :timestamp,         null: false
    String   :type,              null: false, size: 255
    String   :actor,             null: false, size: 255
    String   :actor_type,        null: false, size: 255
    String   :actor_name,        size: 255
    String   :actor_username,    size: 255
    String   :actee,             null: false, size: 255
    String   :actee_type,        null: false, size: 255
    String   :actee_name,        size: 255
    Text     :metadata,          null: false
    String   :space_guid,        size: 255
    String   :organization_guid, size: 255

    index :guid, unique: true
    index %i[created_at guid], name: :events_created_at_guid_index
    index %i[updated_at guid], name: :events_updated_at_guid_index
    index :actee, name: :events_actee_index
    index :space_guid
    index :organization_guid
    index :actee_type
    index %i[timestamp id]
  end
end

# --- Data Seeding ---
# For the org benchmark, we need a "hot org" that is COMPLETELY quiet during
# the most recent QUIET_DAYS. org_guids[0] gets all hot_actee events (~40% of
# total = ~2M rows) during the ACTIVE period. During the quiet period, ALL
# other-actee events are routed to non-hot orgs (org_guids[1..NUM_ORGS]).
# This simulates an org that has gone fully idle.
def seed_data
  hot_actee_count = (ROW_COUNT * HOT_ACTEE_FRACTION).to_i
  other_count = ROW_COUNT - hot_actee_count

  hot_actee = SecureRandom.uuid
  space_guids = Array.new(NUM_SPACES) { SecureRandom.uuid }
  hot_spaces = space_guids[0...HOT_ACTEE_SPACES]
  org_guids = Array.new(NUM_ORGS) { SecureRandom.uuid }
  other_actees = Array.new(NUM_OTHER_ACTEES) { SecureRandom.uuid }
  start_time = Time.now - (86_400 * TOTAL_DAYS)

  puts "Seeding #{ROW_COUNT} events with temporal skew..."
  non_hot_orgs = org_guids[1..]
  puts "  Hot org: #{org_guids[0]}"
  puts "  Hot org ACTIVE period: days 1-#{ACTIVE_DAYS} (oldest #{ACTIVE_DAYS} days)"
  puts "  Hot org QUIET period:  days #{ACTIVE_DAYS + 1}-#{TOTAL_DAYS} (most recent #{QUIET_DAYS} days -- ZERO events in hot org)"
  puts "  During quiet period, other actees' events go ONLY to #{non_hot_orgs.length} non-hot orgs"
  puts "  Other actees: #{NUM_OTHER_ACTEES} across #{NUM_SPACES} spaces, #{NUM_ORGS} orgs"

  batch_size = 5000
  inserted = 0

  (hot_actee_count / batch_size).times do |batch_idx|
    rows = batch_size.times.map do |i|
      n = (batch_idx * batch_size) + i
      # Hot org events compressed into first ACTIVE_DAYS only
      ts = start_time + (n * (86_400 * ACTIVE_DAYS.to_f / hot_actee_count))
      {
        guid: SecureRandom.uuid, created_at: ts, updated_at: ts, timestamp: ts,
        type: EVENT_TYPES[n % EVENT_TYPES.length],
        actor: SecureRandom.uuid, actor_type: 'user',
        actor_name: 'user@example.com', actor_username: 'user@example.com',
        actee: hot_actee, actee_type: 'app', actee_name: 'hot-production-app',
        metadata: '{}',
        space_guid: hot_spaces[n % hot_spaces.length],
        organization_guid: org_guids[0]
      }
    end
    DB[:events].multi_insert(rows)
    inserted += batch_size
    print "\r  Progress: #{(inserted * 100.0 / ROW_COUNT).round(1)}%" if batch_idx % 20 == 0
  end

  quiet_start = start_time + (86_400 * ACTIVE_DAYS)
  (other_count / batch_size).times do |batch_idx|
    rows = batch_size.times.map do |i|
      n = (batch_idx * batch_size) + i
      # Other actees spread across ALL TOTAL_DAYS (including the quiet period)
      ts = start_time + (n * (86_400 * TOTAL_DAYS.to_f / other_count))
      # During quiet period, other events go ONLY to non-hot orgs.
      # During active period, other events go to ALL orgs (including hot one).
      og = if ts >= quiet_start
             non_hot_orgs[n % non_hot_orgs.length]
           else
             org_guids[n % NUM_ORGS]
           end
      {
        guid: SecureRandom.uuid, created_at: ts, updated_at: ts, timestamp: ts,
        type: EVENT_TYPES[n % EVENT_TYPES.length],
        actor: SecureRandom.uuid, actor_type: 'user',
        actor_name: 'other@example.com', actor_username: 'other@example.com',
        actee: other_actees[n % NUM_OTHER_ACTEES], actee_type: 'app',
        actee_name: "app-#{n % NUM_OTHER_ACTEES}",
        metadata: '{}',
        space_guid: space_guids[n % NUM_SPACES],
        organization_guid: og
      }
    end
    DB[:events].multi_insert(rows)
    inserted += batch_size
    print "\r  Progress: #{(inserted * 100.0 / ROW_COUNT).round(1)}%" if batch_idx % 20 == 0
  end

  puts "\r  Progress: 100.0% - Complete!                "
  puts '  Running ANALYZE...'
  analyze_table

  { hot_actee: hot_actee, hot_spaces: hot_spaces, space_guids: space_guids, org_guids: org_guids }
end

# --- Index Management ---
def add_idx(idx)
  unless DB.indexes(:events).key?(idx[:name])
    puts "  Adding index #{idx[:name]}..."
    DB.alter_table(:events) { add_index idx[:cols], name: idx[:name] }
  end
  analyze_table
end

def drop_idx(idx)
  if DB.indexes(:events).key?(idx[:name])
    puts "  Dropping index #{idx[:name]}..."
    DB.alter_table(:events) { drop_index nil, name: idx[:name] }
  end
  analyze_table
end

def ensure_only_indexes(*keep)
  ALL_INDEXES.each { |idx| keep.include?(idx) ? add_idx(idx) : drop_idx(idx) }
end

# --- Query Builder ---
def q(arr) = arr.map { |v| "'#{v}'" }.join(', ')

# Build query with simple permission clause: (1 = 0) OR organization_guid IN (...)
# This represents an org auditor with NO space roles.
# permissions.rb:290-299 generates: (1 = 0) OR organization_guid IN (...)
def build_query_simple(params)
  e = qi('events')
  id = qi('id')
  og = qi('organization_guid')
  t = qi('type')
  ca = qi('created_at')
  g = qi('guid')
  tmp = qi('tmp_deferred_id')

  # No actee, no space_guid in WHERE clause. MySQL must choose between:
  #   - organization_guid single-column index -> finds rows, but must filesort for ORDER BY
  #   - (organization_guid, created_at, guid) composite -> finds rows AND provides sort order
  <<~SQL.gsub(/\s+/, ' ').strip
    SELECT * FROM #{e}
    INNER JOIN (
        SELECT #{e}.#{id} AS #{tmp}
        FROM #{e}
        WHERE (((1 = 0) OR (#{og} IN (#{q(params[:og])})))
            AND (#{t} IN (#{q(params[:types])})))
        ORDER BY #{e}.#{ca} DESC, #{e}.#{g} DESC
        LIMIT 10 OFFSET 0
    ) AS tmp_deferred_table ON (#{e}.#{id} = tmp_deferred_table.#{tmp})
    WHERE (((1 = 0) OR (#{og} IN (#{q(params[:og])})))
        AND (#{t} IN (#{q(params[:types])})))
    ORDER BY #{e}.#{ca} DESC, #{e}.#{g} DESC
  SQL
end

# Build query with realistic permission clause: space_guid IN (...) OR organization_guid IN (...)
# Plus explicit organization_guid filter from API param (event_list_fetcher.rb:28).
# This represents a user with BOTH org auditor and space roles who passes ?organization_guids=X.
def build_query_realistic(params)
  e = qi('events')
  id = qi('id')
  sg = qi('space_guid')
  og = qi('organization_guid')
  t = qi('type')
  ca = qi('created_at')
  g = qi('guid')
  tmp = qi('tmp_deferred_id')

  # The permission OR plus an explicit AND organization_guid from the API parameter.
  # MySQL may use the explicit AND for index seek despite the permission OR.
  <<~SQL.gsub(/\s+/, ' ').strip
    SELECT * FROM #{e}
    INNER JOIN (
        SELECT #{e}.#{id} AS #{tmp}
        FROM #{e}
        WHERE (((#{sg} IN (#{q(params[:sg])})) OR (#{og} IN (#{q(params[:og])})))
            AND (#{og} IN (#{q(params[:explicit_og])}))
            AND (#{t} IN (#{q(params[:types])})))
        ORDER BY #{e}.#{ca} DESC, #{e}.#{g} DESC
        LIMIT 10 OFFSET 0
    ) AS tmp_deferred_table ON (#{e}.#{id} = tmp_deferred_table.#{tmp})
    WHERE (((#{sg} IN (#{q(params[:sg])})) OR (#{og} IN (#{q(params[:og])})))
        AND (#{og} IN (#{q(params[:explicit_og])}))
        AND (#{t} IN (#{q(params[:types])})))
    ORDER BY #{e}.#{ca} DESC, #{e}.#{g} DESC
  SQL
end

# --- EXPLAIN ---
def capture_explain(query)
  if IS_POSTGRES
    DB.fetch("EXPLAIN (ANALYZE, BUFFERS) #{query}").map { |r| r.values.first }
  else
    DB.fetch("EXPLAIN FORMAT=TRADITIONAL #{query}").all
  end
rescue StandardError => e
  puts "  EXPLAIN error: #{e.message}"
  []
end

def print_explain(rows)
  return puts('    (no EXPLAIN data)') if rows.empty?

  if IS_POSTGRES
    rows.each { |line| puts "    #{line}" }
  else
    rows.each do |r|
      puts "    [#{r[:id]}] #{r[:select_type]} | table=#{r[:table]} type=#{r[:type]} " \
           "key=#{r[:key]} rows=#{r[:rows]} filtered=#{r[:filtered]}% | #{r[:Extra]}"
    end
  end
end

# --- Benchmark Runner ---
def run_benchmark(label, query)
  begin
    DB.run('FLUSH STATUS')
  rescue StandardError
    nil
  end
  WARMUP_RUNS.times { DB.fetch(query).all }

  times = BENCHMARK_RUNS.times.map { Benchmark.realtime { DB.fetch(query).all } }
  avg = times.sum / times.length
  explain_rows = capture_explain(query)

  puts "\n  #{'=' * 86}"
  puts "  #{label}"
  puts "  #{'=' * 86}"
  puts "  Avg: #{fmt(avg)} | Min: #{fmt(times.min)} | Max: #{fmt(times.max)}"
  puts '  EXPLAIN:'
  print_explain(explain_rows)

  { label: label, avg_ms: (avg * 1000).round(1), min_ms: (times.min * 1000).round(1),
    max_ms: (times.max * 1000).round(1) }
end

def fmt(seconds)
  ms = seconds * 1000
  ms >= 1000 ? "#{(ms / 1000.0).round(2)} s" : "#{ms.round(1)} ms"
end

# rubocop:disable Style/FormatStringToken
def print_results(title, description, results)
  puts
  puts "  #{title}"
  puts "  #{description}"
  puts
  puts '  Configuration                                                    Avg          Min          Max'
  puts '  ' + ('-' * 91)
  results.each do |r|
    puts sprintf('  %-55s %12s %12s %12s', r[:label][0..54],
                 "#{r[:avg_ms]} ms", "#{r[:min_ms]} ms", "#{r[:max_ms]} ms")
  end
  puts '  ' + ('-' * 91)

  b = results[0][:avg_ms]
  return unless b > 0

  puts
  puts '  Improvement vs baseline:'
  results[1..].each do |r|
    speedup = b / [r[:avg_ms], 0.1].max
    pct = ((b - r[:avg_ms]) / b * 100).round(1)
    puts sprintf('    %-53s %+8.1f%%  (%7.1fx faster)', r[:label][0..52], pct, speedup)
  end
end
# rubocop:enable Style/FormatStringToken

# --- Main ---
db_type = IS_POSTGRES ? 'PostgreSQL' : 'MySQL'

puts
puts '#' * 90
puts "#  SCENARIO C: ORG-SCOPED BROWSE BENCHMARK (#{db_type})"
puts '#  Proves Index 3: (organization_guid, created_at, guid)'
puts '#' * 90
puts
puts "Database:    #{db_version}"
buf = buffer_info
puts "#{buf[:label]}: #{(buf[:bytes] / 1024.0 / 1024).round(0)} MB"
puts "Row count:   #{ROW_COUNT}"
puts "Temporal:    Hot org active days 1-#{ACTIVE_DAYS}, quiet days #{ACTIVE_DAYS + 1}-#{TOTAL_DAYS}"
puts

setup_schema
seed_info = seed_data

hot_org = seed_info[:org_guids][0]
org_count = DB[:events].where(organization_guid: hot_org).count
total = DB[:events].count
tsize = table_size_bytes

puts
puts 'Verification:'
puts "  Total events:       #{total}"
puts "  Events in hot org:  #{org_count} (#{(org_count * 100.0 / total).round(1)}%)"
puts "  Table size:         #{(tsize / 1024.0 / 1024).round(1)} MB"
puts "  #{buf[:label]}:    #{(buf[:bytes] / 1024.0 / 1024).round(0)} MB"
puts "  ** Table LARGER than #{buf[:label]} -- realistic I/O pressure **" if tsize > buf[:bytes]

# ===== Part 1: Simple permission, single organization_guid =====
params_single = {
  og: [seed_info[:org_guids][0]],
  types: QUERY_TYPES
}
query_single = build_query_simple(params_single)

puts
puts "Part 1: Simple permission — single organization_guid (#{org_count} matching rows) + 17 types"
puts '        This is the common pattern and what Index 3 is designed for.'
puts

results_single = []

puts '--- Config 1: BASELINE ---'
ensure_only_indexes
results_single << run_benchmark('BASELINE (no composite indexes)', query_single)

puts "\n--- Config 2: INDEX 1 ONLY ---"
ensure_only_indexes(INDEX_1)
results_single << run_benchmark('INDEX 1 ONLY: (actee, created_at, guid)', query_single)

puts "\n--- Config 3: INDEX 2 ONLY ---"
ensure_only_indexes(INDEX_2)
results_single << run_benchmark('INDEX 2 ONLY: (space_guid, created_at, guid)', query_single)

puts "\n--- Config 4: INDEX 3 ONLY ---"
ensure_only_indexes(INDEX_3)
results_single << run_benchmark('INDEX 3 ONLY: (organization_guid, created_at, guid)', query_single)

puts "\n--- Config 5: ALL THREE INDEXES ---"
ensure_only_indexes(INDEX_1, INDEX_2, INDEX_3)
results_single << run_benchmark('ALL THREE INDEXES', query_single)

# ===== Part 2: Simple permission, multiple organization_guids (IN-clause limitation) =====
params_multi = {
  og: seed_info[:org_guids][0..2],
  types: QUERY_TYPES
}
query_multi = build_query_simple(params_multi)
multi_count = seed_info[:org_guids][0..2].sum { |og| DB[:events].where(organization_guid: og).count }

puts "\n\n#{'#' * 60}"
puts '#  Part 2: Multiple organization_guids (IN-clause limitation test)'
puts '#' * 60

puts
puts "  Multiple organization_guids IN (...) — 3 orgs (#{multi_count} rows total)"
puts '  Note: Multi-value IN on leading index column may prevent ordered index scan.'
puts

results_multi = []

puts '--- Config 1: BASELINE ---'
ensure_only_indexes
results_multi << run_benchmark('BASELINE (no composite indexes)', query_multi)

puts "\n--- Config 2: INDEX 3 ONLY ---"
ensure_only_indexes(INDEX_3)
results_multi << run_benchmark('INDEX 3 ONLY: (organization_guid, created_at, guid)', query_multi)

puts "\n--- Config 3: ALL THREE INDEXES ---"
ensure_only_indexes(INDEX_1, INDEX_2, INDEX_3)
results_multi << run_benchmark('ALL THREE INDEXES', query_multi)

# ===== Part 3: Realistic permission (space_guid IN (...) OR organization_guid IN (...)) =====
# User with both org auditor and space developer roles, plus explicit organization_guids param.
params_realistic = {
  sg: seed_info[:hot_spaces][0..2],
  og: seed_info[:org_guids][0..2],
  explicit_og: [seed_info[:org_guids][0]],
  types: QUERY_TYPES
}
query_realistic = build_query_realistic(params_realistic)

puts "\n\n#{'#' * 60}"
puts '#  Part 3: Realistic permission — space_guid IN (...) OR organization_guid IN (...)'
puts '#  Plus explicit organization_guids param from API call'
puts '#' * 60

puts
puts "  Realistic OR with explicit organization_guid filter (#{org_count} rows in org)"
puts '  Tests whether the explicit AND organization_guid enables Index 3 despite the OR.'
puts

results_realistic = []

puts '--- Config 1: BASELINE ---'
ensure_only_indexes
results_realistic << run_benchmark('BASELINE (no composite indexes)', query_realistic)

puts "\n--- Config 2: INDEX 3 ONLY ---"
ensure_only_indexes(INDEX_3)
results_realistic << run_benchmark('INDEX 3 ONLY: (organization_guid, created_at, guid)', query_realistic)

puts "\n--- Config 3: ALL THREE INDEXES ---"
ensure_only_indexes(INDEX_1, INDEX_2, INDEX_3)
results_realistic << run_benchmark('ALL THREE INDEXES', query_realistic)

# --- Summary ---
puts "\n\n#{'#' * 90}"
puts "#  SCENARIO C RESULTS: Org-Scoped Browse (#{db_type})"
puts '#' * 90

print_results(
  "PART 1: Single organization_guid (#{org_count} rows in org)",
  'Expected: Index 3 (organization_guid, created_at, guid) should fix this.',
  results_single
)

puts

print_results(
  "PART 2: Multiple organization_guids IN (...) — 3 orgs (#{multi_count} rows total)",
  'Note: Multi-value IN on leading index column may prevent ordered index scan.',
  results_multi
)

puts

print_results(
  'PART 3: Realistic permission — space_guid IN (...) OR org_guid IN (...) + explicit org_guid',
  'Tests whether explicit AND organization_guid enables Index 3 despite the permission OR.',
  results_realistic
)

puts
puts 'Done.'
# rubocop:enable Rails/SquishedSQLHeredocs

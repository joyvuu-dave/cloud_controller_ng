require 'spec_helper'
require 'request_spec_shared_examples'

RSpec.describe 'App Usage Snapshots' do
  let(:user) { make_user }
  let(:admin_header) { admin_headers_for(user) }
  let(:org) { VCAP::CloudController::Organization.make }
  let(:space) { VCAP::CloudController::Space.make(organization: org) }

  describe 'POST /v3/app_usage/snapshots' do
    let(:api_call) { ->(user_headers) { post '/v3/app_usage/snapshots', nil, user_headers } }

    let(:expected_codes_and_responses) do
      h = Hash.new { |hash, key| hash[key] = { code: 403 } }
      h['admin'] = { code: 202 }
      h
    end

    it_behaves_like 'permissions for single object endpoint', ALL_PERMISSIONS

    context 'when the user is an admin' do
      it 'creates a usage snapshot asynchronously' do
        post '/v3/app_usage/snapshots', nil, admin_header

        expect(last_response.status).to eq(202)
        expect(last_response.headers['Location']).to match(%r{/v3/jobs/})

        job_guid = last_response.headers['Location'].split('/').last
        get "/v3/jobs/#{job_guid}", nil, admin_header

        expect(last_response.status).to eq(200)
        job_response = Oj.load(last_response.body)
        expect(job_response['operation']).to eq('app_usage_snapshot.generate')
      end

      context 'when a snapshot is already in progress' do
        before do
          VCAP::CloudController::AppUsageSnapshot.create(
            guid: 'in-progress-snapshot',
            checkpoint_event_id: nil,
            created_at: Time.now.utc,
            completed_at: nil,
            instance_count: 0,
            organization_count: 0,
            space_count: 0,
            process_count: 0,
            chunk_count: 0
          )
        end

        it 'returns 409 Conflict' do
          post '/v3/app_usage/snapshots', nil, admin_header

          expect(last_response.status).to eq(409)
          expect(last_response).to have_error_message('An app usage snapshot is already being generated')
        end
      end

      # NOTE: This documents the known race condition behavior.
      # Two concurrent requests could both pass the in-progress check before either
      # creates a snapshot. This is a documented design decision - the race window
      # is small and duplicate checkpoints are harmless (consumers just use the most recent).
      #
      # The check-then-create pattern:
      #   1. Check: existing_snapshot = AppUsageSnapshot.where(completed_at: nil).first
      #   2. Create: AppUsageSnapshot.create(...)
      #
      # Two requests could both pass step 1 before either reaches step 2.
      # This is acceptable because:
      # - The race window is very small (milliseconds)
      # - Duplicate snapshots are harmless (same data, different timestamps)
      # - Consumers use the most recent completed snapshot
      # - Adding a unique constraint would add complexity without significant benefit
      #
      # Testing actual race conditions is non-deterministic, so we don't test it here.
    end

    context 'when the user is not an admin' do
      let(:user_header) { headers_for(user) }

      it 'returns 403 Forbidden' do
        post '/v3/app_usage/snapshots', nil, user_header

        expect(last_response.status).to eq(403)
      end
    end

    context 'when the user is not logged in' do
      it 'returns 401 Unauthorized' do
        post '/v3/app_usage/snapshots', nil, base_json_headers

        expect(last_response.status).to eq(401)
      end
    end
  end

  describe 'GET /v3/app_usage/snapshots/:guid' do
    let!(:snapshot) do
      VCAP::CloudController::AppUsageSnapshot.create(
        guid: 'test-snapshot-guid',
        checkpoint_event_id: 12_345,
        checkpoint_event_created_at: Time.now.utc - 1.hour,
        created_at: Time.now.utc - 1.hour,
        completed_at: Time.now.utc - 59.minutes,
        instance_count: 10,
        organization_count: 2,
        space_count: 3,
        process_count: 5,
        chunk_count: 3
      )
    end

    let(:api_call) { ->(user_headers) { get "/v3/app_usage/snapshots/#{snapshot.guid}", nil, user_headers } }

    let(:snapshot_json) do
      {
        guid: snapshot.guid,
        created_at: iso8601,
        completed_at: iso8601,
        checkpoint_event_id: 12_345,
        checkpoint_event_created_at: iso8601,
        summary: {
          instance_count: 10,
          process_count: 5,
          organization_count: 2,
          space_count: 3,
          chunk_count: 3
        },
        links: {
          self: { href: /#{Regexp.escape("/v3/app_usage/snapshots/#{snapshot.guid}")}/ },
          checkpoint_event: { href: %r{/v3/app_usage_events/12345} },
          chunks: { href: /#{Regexp.escape("/v3/app_usage/snapshots/#{snapshot.guid}/chunks")}/ }
        }
      }
    end

    let(:expected_codes_and_responses) do
      h = Hash.new { |hash, key| hash[key] = { code: 404 } }
      h['admin'] = { code: 200, response_object: snapshot_json }
      h['admin_read_only'] = { code: 200, response_object: snapshot_json }
      h['global_auditor'] = { code: 200, response_object: snapshot_json }
      h
    end

    it_behaves_like 'permissions for single object endpoint', ALL_PERMISSIONS

    context 'when the snapshot does not exist' do
      it 'returns 404' do
        get '/v3/app_usage/snapshots/does-not-exist', nil, admin_header

        expect(last_response.status).to eq(404)
        expect(last_response).to have_error_message('App usage snapshot not found')
      end
    end
  end

  describe 'GET /v3/app_usage/snapshots' do
    let!(:snapshot1) do
      VCAP::CloudController::AppUsageSnapshot.create(
        guid: 'snapshot-1',
        checkpoint_event_id: 100,
        checkpoint_event_created_at: Time.now.utc - 2.hours,
        created_at: Time.now.utc - 2.hours,
        completed_at: Time.now.utc - 119.minutes,
        instance_count: 5,
        organization_count: 1,
        space_count: 1,
        process_count: 2,
        chunk_count: 1
      )
    end

    let!(:snapshot2) do
      VCAP::CloudController::AppUsageSnapshot.create(
        guid: 'snapshot-2',
        checkpoint_event_id: 200,
        checkpoint_event_created_at: Time.now.utc - 1.hour,
        created_at: Time.now.utc - 1.hour,
        completed_at: Time.now.utc - 59.minutes,
        instance_count: 10,
        organization_count: 2,
        space_count: 2,
        process_count: 4,
        chunk_count: 2
      )
    end

    let(:api_call) { ->(user_headers) { get '/v3/app_usage/snapshots', nil, user_headers } }

    let(:expected_codes_and_responses) do
      h = Hash.new { |hash, key| hash[key] = { code: 200, response_objects: [] } }
      h['admin'] = { code: 200, response_objects: [hash_including(guid: 'snapshot-1'), hash_including(guid: 'snapshot-2')] }
      h['admin_read_only'] = { code: 200, response_objects: [hash_including(guid: 'snapshot-1'), hash_including(guid: 'snapshot-2')] }
      h['global_auditor'] = { code: 200, response_objects: [hash_including(guid: 'snapshot-1'), hash_including(guid: 'snapshot-2')] }
      h
    end

    it_behaves_like 'permissions for list endpoint', ALL_PERMISSIONS

    context 'when the user is an admin' do
      it 'returns all snapshots' do
        get '/v3/app_usage/snapshots', nil, admin_header

        expect(last_response.status).to eq(200)
        response = Oj.load(last_response.body)
        expect(response['resources'].length).to eq(2)
        expect(response['resources'].pluck('guid')).to contain_exactly('snapshot-1', 'snapshot-2')
      end

      it 'supports pagination' do
        get '/v3/app_usage/snapshots?per_page=1', nil, admin_header

        expect(last_response.status).to eq(200)
        response = Oj.load(last_response.body)
        expect(response['resources'].length).to eq(1)
        expect(response['pagination']['total_results']).to eq(2)
      end
    end
  end

  describe 'GET /v3/app_usage/snapshots/:guid/chunks' do
    let!(:snapshot) do
      VCAP::CloudController::AppUsageSnapshot.create(
        guid: 'test-snapshot-guid',
        checkpoint_event_id: 12_345,
        checkpoint_event_created_at: Time.now.utc - 1.hour,
        created_at: Time.now.utc - 1.hour,
        completed_at: Time.now.utc - 59.minutes,
        instance_count: 15,
        organization_count: 2,
        space_count: 2,
        process_count: 4,
        chunk_count: 2
      )
    end

    let!(:chunk1) do
      VCAP::CloudController::AppUsageSnapshotChunk.create(
        app_usage_snapshot_id: snapshot.id,
        organization_guid: 'org-1-guid',
        space_guid: 'space-1-guid',
        chunk_index: 0,
        process_count: 2,
        instance_count: 10,
        processes: [
          { 'app_guid' => 'app-1', 'process_type' => 'web', 'instances' => 5 },
          { 'app_guid' => 'app-1', 'process_type' => 'worker', 'instances' => 5 }
        ]
      )
    end

    let!(:chunk2) do
      VCAP::CloudController::AppUsageSnapshotChunk.create(
        app_usage_snapshot_id: snapshot.id,
        organization_guid: 'org-2-guid',
        space_guid: 'space-2-guid',
        chunk_index: 0,
        process_count: 1,
        instance_count: 5,
        processes: [
          { 'app_guid' => 'app-2', 'process_type' => 'web', 'instances' => 5 }
        ]
      )
    end

    context 'when the user is an admin' do
      it 'returns the chunk details for the snapshot' do
        get "/v3/app_usage/snapshots/#{snapshot.guid}/chunks", nil, admin_header

        expect(last_response.status).to eq(200)
        response = Oj.load(last_response.body)
        expect(response['resources'].length).to eq(2)
        expect(response['resources'].pluck('space_guid')).to contain_exactly('space-1-guid', 'space-2-guid')
      end

      it 'includes process details in each chunk record' do
        get "/v3/app_usage/snapshots/#{snapshot.guid}/chunks", nil, admin_header

        expect(last_response.status).to eq(200)
        response = Oj.load(last_response.body)
        chunk1_response = response['resources'].find { |r| r['space_guid'] == 'space-1-guid' }

        expect(chunk1_response['organization_guid']).to eq('org-1-guid')
        expect(chunk1_response['chunk_index']).to eq(0)
        expect(chunk1_response['process_count']).to eq(2)
        expect(chunk1_response['instance_count']).to eq(10)
        expect(chunk1_response['processes'].length).to eq(2)
      end

      it 'supports pagination' do
        get "/v3/app_usage/snapshots/#{snapshot.guid}/chunks?per_page=1", nil, admin_header

        expect(last_response.status).to eq(200)
        response = Oj.load(last_response.body)
        expect(response['resources'].length).to eq(1)
        expect(response['pagination']['total_results']).to eq(2)
      end
    end

    context 'when the snapshot is still processing' do
      let!(:processing_snapshot) do
        VCAP::CloudController::AppUsageSnapshot.create(
          guid: 'processing-snapshot-guid',
          checkpoint_event_id: nil,
          created_at: Time.now.utc,
          completed_at: nil,
          instance_count: 0,
          organization_count: 0,
          space_count: 0,
          process_count: 0,
          chunk_count: 0
        )
      end

      it 'returns 422 Unprocessable Entity' do
        get "/v3/app_usage/snapshots/#{processing_snapshot.guid}/chunks", nil, admin_header

        expect(last_response.status).to eq(422)
        expect(last_response).to have_error_message('Snapshot is still processing')
      end
    end

    context 'when the snapshot does not exist' do
      it 'returns 404' do
        get '/v3/app_usage/snapshots/does-not-exist/chunks', nil, admin_header

        expect(last_response.status).to eq(404)
        expect(last_response).to have_error_message('App usage snapshot not found')
      end
    end

    context 'when the user is not an admin' do
      let(:user_header) { headers_for(user) }

      it 'returns 404' do
        get "/v3/app_usage/snapshots/#{snapshot.guid}/chunks", nil, user_header

        expect(last_response.status).to eq(404)
      end
    end
  end
end

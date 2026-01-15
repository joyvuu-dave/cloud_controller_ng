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
            process_count: 0,
            organization_count: 0,
            space_count: 0
          )
        end

        it 'returns 409 Conflict' do
          post '/v3/app_usage/snapshots', nil, admin_header

          expect(last_response.status).to eq(409)
          expect(last_response).to have_error_message('An app usage snapshot is already being generated')
        end
      end
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
        process_count: 10,
        organization_count: 2,
        space_count: 3
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
          process_count: 10,
          organization_count: 2,
          space_count: 3
        },
        links: {
          self: { href: /#{Regexp.escape("/v3/app_usage/snapshots/#{snapshot.guid}")}/ },
          details: { href: /#{Regexp.escape("/v3/app_usage/snapshots/#{snapshot.guid}/details")}/ },
          checkpoint_event: { href: %r{/v3/app_usage_events/12345} }
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
        expect(last_response).to have_error_message('Usage snapshot not found')
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
        process_count: 5,
        organization_count: 1,
        space_count: 1
      )
    end

    let!(:snapshot2) do
      VCAP::CloudController::AppUsageSnapshot.create(
        guid: 'snapshot-2',
        checkpoint_event_id: 200,
        checkpoint_event_created_at: Time.now.utc - 1.hour,
        created_at: Time.now.utc - 1.hour,
        completed_at: Time.now.utc - 59.minutes,
        process_count: 10,
        organization_count: 2,
        space_count: 2
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

  describe 'GET /v3/app_usage/snapshots/:guid/details' do
    let!(:snapshot) do
      VCAP::CloudController::AppUsageSnapshot.create(
        guid: 'test-snapshot',
        checkpoint_event_id: 100,
        checkpoint_event_created_at: Time.now.utc,
        created_at: Time.now.utc,
        completed_at: Time.now.utc,
        process_count: 2,
        organization_count: 1,
        space_count: 1
      )
    end

    let!(:detail1) do
      VCAP::CloudController::AppUsageSnapshotDetail.create(
        app_usage_snapshot: snapshot,
        organization_guid: org.guid,
        space_guid: space.guid,
        app_guid: 'app-1',
        process_guid: 'process-1',
        process_type: 'web',
        instances: 3
      )
    end

    let!(:detail2) do
      VCAP::CloudController::AppUsageSnapshotDetail.create(
        app_usage_snapshot: snapshot,
        organization_guid: org.guid,
        space_guid: space.guid,
        app_guid: 'app-2',
        process_guid: 'process-2',
        process_type: 'worker',
        instances: 2
      )
    end

    let(:api_call) { ->(user_headers) { get "/v3/app_usage/snapshots/#{snapshot.guid}/details", nil, user_headers } }

    let(:expected_codes_and_responses) do
      h = Hash.new { |hash, key| hash[key] = { code: 404 } }
      h['admin'] = { code: 200, response_objects: [hash_including(process_guid: 'process-1'), hash_including(process_guid: 'process-2')] }
      h['admin_read_only'] = { code: 200, response_objects: [hash_including(process_guid: 'process-1'), hash_including(process_guid: 'process-2')] }
      h['global_auditor'] = { code: 200, response_objects: [hash_including(process_guid: 'process-1'), hash_including(process_guid: 'process-2')] }
      h
    end

    it_behaves_like 'permissions for list endpoint', ALL_PERMISSIONS

    context 'when the user is an admin' do
      it 'returns all details for the snapshot' do
        get "/v3/app_usage/snapshots/#{snapshot.guid}/details", nil, admin_header

        expect(last_response.status).to eq(200)
        response = Oj.load(last_response.body)
        expect(response['resources'].length).to eq(2)
      end

      it 'supports filtering by organization_guids' do
        get "/v3/app_usage/snapshots/#{snapshot.guid}/details?organization_guids=#{org.guid}", nil, admin_header

        expect(last_response.status).to eq(200)
        response = Oj.load(last_response.body)
        expect(response['resources'].length).to eq(2)
      end

      it 'supports filtering by space_guids' do
        get "/v3/app_usage/snapshots/#{snapshot.guid}/details?space_guids=#{space.guid}", nil, admin_header

        expect(last_response.status).to eq(200)
        response = Oj.load(last_response.body)
        expect(response['resources'].length).to eq(2)
      end

      it 'returns empty array for non-matching filters' do
        get "/v3/app_usage/snapshots/#{snapshot.guid}/details?organization_guids=non-existent", nil, admin_header

        expect(last_response.status).to eq(200)
        response = Oj.load(last_response.body)
        expect(response['resources'].length).to eq(0)
      end
    end

    context 'when the snapshot does not exist' do
      it 'returns 404' do
        get '/v3/app_usage/snapshots/does-not-exist/details', nil, admin_header

        expect(last_response.status).to eq(404)
        expect(last_response).to have_error_message('Usage snapshot not found')
      end
    end
  end
end

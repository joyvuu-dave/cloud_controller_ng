require 'spec_helper'

RSpec.describe 'Service Usage Snapshots' do
  let(:user) { VCAP::CloudController::User.make }
  let(:admin_header) { admin_headers_for(user) }

  describe 'POST /v3/service_usage/snapshots' do
    it 'creates a snapshot generation job and returns 202' do
      post '/v3/service_usage/snapshots', nil, admin_header

      expect(last_response.status).to eq(202)
      expect(last_response.headers['Location']).to match(%r{/v3/jobs/})
    end

    it 'requires admin permissions' do
      post '/v3/service_usage/snapshots', nil, headers_for(user)

      expect(last_response.status).to eq(403)
    end

    context 'when a snapshot is already in progress' do
      before do
        VCAP::CloudController::ServiceUsageSnapshot.make(completed_at: nil)
      end

      it 'returns 409 conflict' do
        post '/v3/service_usage/snapshots', nil, admin_header

        expect(last_response.status).to eq(409)
        expect(parsed_response['errors'].first['title']).to match(/ServiceUsageSnapshotGenerationInProgress/)
      end
    end
  end

  describe 'GET /v3/service_usage/snapshots/:guid' do
    let(:snapshot) { VCAP::CloudController::ServiceUsageSnapshot.make(service_instance_count: 10, completed_at: Time.now.utc) }

    it 'returns the snapshot' do
      get "/v3/service_usage/snapshots/#{snapshot.guid}", nil, admin_header

      expect(last_response.status).to eq(200)
      expect(parsed_response['guid']).to eq(snapshot.guid)
      expect(parsed_response['summary']['service_instance_count']).to eq(10)
    end

    it 'returns 404 for non-admin users' do
      get "/v3/service_usage/snapshots/#{snapshot.guid}", nil, headers_for(user)

      expect(last_response.status).to eq(404)
    end

    it 'returns 404 for non-existent snapshot' do
      get '/v3/service_usage/snapshots/nonexistent-guid', nil, admin_header

      expect(last_response.status).to eq(404)
    end
  end

  describe 'GET /v3/service_usage/snapshots' do
    let!(:snapshot1) { VCAP::CloudController::ServiceUsageSnapshot.make(service_instance_count: 5, completed_at: Time.now.utc) }
    let!(:snapshot2) { VCAP::CloudController::ServiceUsageSnapshot.make(service_instance_count: 10, completed_at: Time.now.utc) }

    it 'lists all snapshots' do
      get '/v3/service_usage/snapshots', nil, admin_header

      expect(last_response.status).to eq(200)
      expect(parsed_response['pagination']['total_results']).to eq(2)
      expect(parsed_response['resources'].pluck('guid')).to contain_exactly(snapshot1.guid, snapshot2.guid)
    end

    it 'returns empty list for non-admin users' do
      get '/v3/service_usage/snapshots', nil, headers_for(user)

      expect(last_response.status).to eq(200)
      expect(parsed_response['pagination']['total_results']).to eq(0)
    end

    it 'supports pagination' do
      get '/v3/service_usage/snapshots?per_page=1', nil, admin_header

      expect(last_response.status).to eq(200)
      expect(parsed_response['pagination']['total_results']).to eq(2)
      expect(parsed_response['resources'].length).to eq(1)
    end
  end

  describe 'GET /v3/service_usage/snapshots/:guid/spaces' do
    let!(:snapshot) do
      VCAP::CloudController::ServiceUsageSnapshot.create(
        guid: 'test-service-snapshot-guid',
        checkpoint_event_id: 12_345,
        checkpoint_event_created_at: Time.now.utc - 1.hour,
        created_at: Time.now.utc - 1.hour,
        completed_at: Time.now.utc - 59.minutes,
        service_instance_count: 5,
        organization_count: 2,
        space_count: 2
      )
    end

    let!(:space1) do
      VCAP::CloudController::ServiceUsageSnapshotSpace.create(
        service_usage_snapshot_id: snapshot.id,
        space_guid: 'space-1-guid',
        organization_guid: 'org-1-guid',
        service_instance_count: 3,
        service_instances: [
          { 'guid' => 'si-1', 'name' => 'my-db', 'type' => 'managed' },
          { 'guid' => 'si-2', 'name' => 'my-cache', 'type' => 'managed' },
          { 'guid' => 'si-3', 'name' => 'my-creds', 'type' => 'user_provided' }
        ]
      )
    end

    let!(:space2) do
      VCAP::CloudController::ServiceUsageSnapshotSpace.create(
        service_usage_snapshot_id: snapshot.id,
        space_guid: 'space-2-guid',
        organization_guid: 'org-2-guid',
        service_instance_count: 2,
        service_instances: [
          { 'guid' => 'si-4', 'name' => 'other-db', 'type' => 'managed' },
          { 'guid' => 'si-5', 'name' => 'other-cache', 'type' => 'managed' }
        ]
      )
    end

    context 'when the user is an admin' do
      it 'returns the space details for the snapshot' do
        get "/v3/service_usage/snapshots/#{snapshot.guid}/spaces", nil, admin_header

        expect(last_response.status).to eq(200)
        expect(parsed_response['resources'].length).to eq(2)
        expect(parsed_response['resources'].pluck('space_guid')).to contain_exactly('space-1-guid', 'space-2-guid')
      end

      it 'includes service instance details in each space record' do
        get "/v3/service_usage/snapshots/#{snapshot.guid}/spaces", nil, admin_header

        expect(last_response.status).to eq(200)
        space1_response = parsed_response['resources'].find { |r| r['space_guid'] == 'space-1-guid' }

        expect(space1_response['organization_guid']).to eq('org-1-guid')
        expect(space1_response['service_instance_count']).to eq(3)
        expect(space1_response['service_instances'].length).to eq(3)
      end

      it 'supports pagination' do
        get "/v3/service_usage/snapshots/#{snapshot.guid}/spaces?per_page=1", nil, admin_header

        expect(last_response.status).to eq(200)
        expect(parsed_response['resources'].length).to eq(1)
        expect(parsed_response['pagination']['total_results']).to eq(2)
      end
    end

    context 'when the snapshot is still processing' do
      let!(:processing_snapshot) do
        VCAP::CloudController::ServiceUsageSnapshot.create(
          guid: 'processing-service-snapshot-guid',
          checkpoint_event_id: nil,
          created_at: Time.now.utc,
          completed_at: nil,
          service_instance_count: 0,
          organization_count: 0,
          space_count: 0
        )
      end

      it 'returns 422 Unprocessable Entity' do
        get "/v3/service_usage/snapshots/#{processing_snapshot.guid}/spaces", nil, admin_header

        expect(last_response.status).to eq(422)
      end
    end

    context 'when the snapshot does not exist' do
      it 'returns 404' do
        get '/v3/service_usage/snapshots/does-not-exist/spaces', nil, admin_header

        expect(last_response.status).to eq(404)
      end
    end

    context 'when the user is not an admin' do
      it 'returns 404' do
        get "/v3/service_usage/snapshots/#{snapshot.guid}/spaces", nil, headers_for(user)

        expect(last_response.status).to eq(404)
      end
    end
  end
end

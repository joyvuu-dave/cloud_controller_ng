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

    it 'requires admin permissions' do
      get "/v3/service_usage/snapshots/#{snapshot.guid}", nil, headers_for(user)

      expect(last_response.status).to eq(403)
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

    it 'requires admin permissions' do
      get '/v3/service_usage/snapshots', nil, headers_for(user)

      expect(last_response.status).to eq(403)
    end

    it 'supports pagination' do
      get '/v3/service_usage/snapshots?per_page=1', nil, admin_header

      expect(last_response.status).to eq(200)
      expect(parsed_response['pagination']['total_results']).to eq(2)
      expect(parsed_response['resources'].length).to eq(1)
    end
  end

  describe 'GET /v3/service_usage/snapshots/:guid/details' do
    let(:org) { VCAP::CloudController::Organization.make }
    let(:space) { VCAP::CloudController::Space.make(organization: org) }
    let(:snapshot) { VCAP::CloudController::ServiceUsageSnapshot.make(completed_at: Time.now.utc) }
    let!(:detail1) do
      VCAP::CloudController::ServiceUsageSnapshotDetail.make(
        service_usage_snapshot: snapshot,
        organization_guid: org.guid,
        space_guid: space.guid,
        service_instance_type: 'managed_service_instance'
      )
    end
    let!(:detail2) do
      VCAP::CloudController::ServiceUsageSnapshotDetail.make(
        service_usage_snapshot: snapshot,
        organization_guid: org.guid,
        space_guid: space.guid,
        service_instance_type: 'user_provided'
      )
    end

    it 'returns snapshot details' do
      get "/v3/service_usage/snapshots/#{snapshot.guid}/details", nil, admin_header

      expect(last_response.status).to eq(200)
      expect(parsed_response['pagination']['total_results']).to eq(2)
      expect(parsed_response['resources'].pluck('service_instance_guid')).to contain_exactly(detail1.service_instance_guid, detail2.service_instance_guid)
    end

    it 'requires admin permissions' do
      get "/v3/service_usage/snapshots/#{snapshot.guid}/details", nil, headers_for(user)

      expect(last_response.status).to eq(403)
    end

    it 'returns 404 for non-existent snapshot' do
      get '/v3/service_usage/snapshots/nonexistent-guid/details', nil, admin_header

      expect(last_response.status).to eq(404)
    end

    it 'supports filtering by organization_guids' do
      get "/v3/service_usage/snapshots/#{snapshot.guid}/details?organization_guids=#{org.guid}", nil, admin_header

      expect(last_response.status).to eq(200)
      expect(parsed_response['pagination']['total_results']).to eq(2)
    end

    it 'supports filtering by space_guids' do
      get "/v3/service_usage/snapshots/#{snapshot.guid}/details?space_guids=#{space.guid}", nil, admin_header

      expect(last_response.status).to eq(200)
      expect(parsed_response['pagination']['total_results']).to eq(2)
    end

    it 'supports pagination' do
      get "/v3/service_usage/snapshots/#{snapshot.guid}/details?per_page=1", nil, admin_header

      expect(last_response.status).to eq(200)
      expect(parsed_response['pagination']['total_results']).to eq(2)
      expect(parsed_response['resources'].length).to eq(1)
    end
  end
end

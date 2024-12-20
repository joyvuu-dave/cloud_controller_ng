require 'spec_helper'
require 'request_spec_shared_examples'

RSpec.describe 'App Usage Consumers' do
  let(:user) { VCAP::CloudController::User.make }
  let(:admin_header) { admin_headers_for(user) }
  let(:space) { VCAP::CloudController::Space.make }
  let(:org) { space.organization }

  describe 'DELETE /v3/app_usage_consumers/:guid' do
    let(:api_call) { ->(user_headers) { delete "/v3/app_usage_consumers/#{app_usage_consumer.consumer_guid}", nil, user_headers } }
    let(:app_usage_consumer) { VCAP::CloudController::AppUsageConsumer.make }

    let(:expected_codes_and_responses) do
      h = Hash.new(
        code: 403,
        response_object: []
      )
      h['admin'] = {
        code: 204,
        response_object: nil
      }
      h['admin_read_only'] = {
        code: 403,
        response_object: [],
        scopes: %w(cloud_controller.admin_read_only)
      }
      h['unauthenticated'] = {
        code: 401,
        response_object: []
      }
      h
    end

    it_behaves_like 'permissions for single object endpoint', ALL_PERMISSIONS

    context 'when the app usage consumer does not exist' do
      it 'returns a 404 for admins' do
        delete '/v3/app_usage_consumers/does-not-exist', nil, admin_header
        expect(last_response.status).to eq 404
        expect(last_response).to have_error_message('AppUsageConsumer not found')
        parsed_response = JSON.parse(last_response.body)
        expect(parsed_response['errors']).to include(include(
          'title' => 'CF-ResourceNotFound',
          'detail' => 'AppUsageConsumer not found',
          'code' => 10010
        ))
      end

      it 'returns 403 for non-admins' do
        set_current_user(user)
        delete '/v3/app_usage_consumers/does-not-exist', nil, headers_for(user)
        expect(last_response.status).to eq 403
      end
    end

    context 'when the user is not logged in' do
      it 'returns 401 for Unauthenticated requests' do
        set_current_user_as_unauthenticated
        delete "/v3/app_usage_consumers/#{app_usage_consumer.consumer_guid}", nil, {}
        expect(last_response.status).to eq(401)
      end
    end
  end
end

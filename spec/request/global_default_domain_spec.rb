require 'spec_helper'

RSpec.describe 'Global default domains Request' do
  let(:user) { VCAP::CloudController::User.make }
  let(:space) { VCAP::CloudController::Space.make }
  let(:org) { space.organization }
  let(:admin_header) { headers_for(user, scopes: %w(cloud_controller.admin)) }
  let(:user_header) { headers_for(user, scopes: []) }

  describe 'GET /v3/domains' do
    describe 'global_default' do
      it 'always lists the global_default domain first' do
        get '/v3/domains', nil, admin_header

        parsed_response = MultiJson.load(last_response.body)

        global_default_values = parsed_response['resources'].map { |r| r['global_default'] }
        expect(global_default_values.first).to be_truthy
        expect(global_default_values.drop(1).all?(false)).to be_truthy
      end
    end
  end
end
require 'spec_helper'

RSpec.describe OrganizationPresenter do
  describe '#to_hash' do
    let(:org) { FactoryBot.create(:organization) }
    before do
      FactoryBot.create(:space, organization: org)
      user = FactoryBot.create(:user)
      user.add_organization org
      user.add_managed_organization org
    end
    subject { OrganizationPresenter.new(org) }

    it 'creates a valid JSON' do
      expect(subject.to_hash).to eq({
        metadata: {
          guid: org.guid,
          created_at: org.created_at.iso8601,
          updated_at: org.updated_at.iso8601,
        },
        entity: {
          name: org.name,
          billing_enabled: org.billing_enabled,
          status: org.status,
          spaces: org.spaces.map { |space| SpacePresenter.new(space).to_hash },
          quota_definition: QuotaDefinitionPresenter.new(org.quota_definition).to_hash,
          managers: org.managers.map { |manager| UserPresenter.new(manager).to_hash }
        }
      })
    end
  end
end
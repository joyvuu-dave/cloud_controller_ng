require 'presenters/v3/base_presenter'
require 'models/helpers/metadata_helpers'
require 'presenters/mixins/metadata_presentation_helpers'

module VCAP::CloudController
  module Presenters
    module V3
      class AppPresenter < BasePresenter
        include VCAP::CloudController::Presenters::Mixins::MetadataPresentationHelpers

        class << self
          # :labels and :annotations come from MetadataPresentationHelpers
          def associated_resources
            super << { buildpack_lifecycle_data: :buildpack_lifecycle_buildpacks }
          end
        end

        def to_hash
          hash = {
            guid: app.guid,
            name: app.name,
            state: app.desired_state,
            created_at: app.created_at,
            updated_at: app.updated_at,
            lifecycle: {
              type: app.lifecycle_type,
              data: app.lifecycle_data.to_hash
            },
            relationships: {
              processes: { data: process_guids },
              space: { data: { guid: app.space_guid } }
            },
            links: build_links,
            metadata: {
              labels: hashified_labels(app.labels),
              annotations: hashified_annotations(app.annotations)
            }
          }

          @decorators.reduce(hash) { |memo, d| d.decorate(memo, [app]) }
        end

        private

        def app
          @resource
        end

        def process_guids
          app.process_guids.map { |guid| { guid: guid } }
        end

        def build_links
          url_builder = VCAP::CloudController::Presenters::ApiUrlBuilder.new

          links = {
            self: { href: url_builder.build_url(path: "/v3/apps/#{app.guid}") },
            environment_variables: { href: url_builder.build_url(path: "/v3/apps/#{app.guid}/environment_variables") },
            space: { href: url_builder.build_url(path: "/v3/spaces/#{app.space_guid}") },
            processes: { href: url_builder.build_url(path: "/v3/apps/#{app.guid}/processes") },
            packages: { href: url_builder.build_url(path: "/v3/apps/#{app.guid}/packages") },
            current_droplet: { href: url_builder.build_url(path: "/v3/apps/#{app.guid}/droplets/current") },
            droplets: { href: url_builder.build_url(path: "/v3/apps/#{app.guid}/droplets") },
            tasks: { href: url_builder.build_url(path: "/v3/apps/#{app.guid}/tasks") },
            start: { href: url_builder.build_url(path: "/v3/apps/#{app.guid}/actions/start"), method: 'POST' },
            stop: { href: url_builder.build_url(path: "/v3/apps/#{app.guid}/actions/stop"), method: 'POST' },
            revisions: { href: url_builder.build_url(path: "/v3/apps/#{app.guid}/revisions") },
            deployed_revisions: { href: url_builder.build_url(path: "/v3/apps/#{app.guid}/revisions/deployed") },
          }

          links.delete_if { |_, v| v.nil? }
        end
      end
    end
  end
end

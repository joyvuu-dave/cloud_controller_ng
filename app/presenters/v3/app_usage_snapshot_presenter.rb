require 'presenters/v3/base_presenter'

module VCAP::CloudController
  module Presenters
    module V3
      class AppUsageSnapshotPresenter < BasePresenter
        def to_hash
          {
            guid: snapshot.guid,
            created_at: snapshot.created_at,
            completed_at: snapshot.completed_at,
            checkpoint_event_id: snapshot.checkpoint_event_id,
            checkpoint_event_created_at: snapshot.checkpoint_event_created_at,
            summary: {
              process_count: snapshot.process_count,
              organization_count: snapshot.organization_count,
              space_count: snapshot.space_count
            },
            links: build_links
          }
        end

        private

        def snapshot
          @resource
        end

        def build_links
          links = {
            self: { href: url_builder.build_url(path: "/v3/app_usage/snapshots/#{snapshot.guid}") },
            details: { href: url_builder.build_url(path: "/v3/app_usage/snapshots/#{snapshot.guid}/details") }
          }

          # Find associated job
          pollable_job = PollableJobModel.where(
            resource_type: 'app_usage_snapshot',
            resource_guid: snapshot.guid
          ).first

          links[:job] = { href: url_builder.build_url(path: "/v3/jobs/#{pollable_job.guid}") } if pollable_job

          if snapshot.checkpoint_event_id && snapshot.checkpoint_event_id > 0
            links[:checkpoint_event] = { href: url_builder.build_url(path: "/v3/app_usage_events/#{snapshot.checkpoint_event_id}") }
          end

          links
        end
      end
    end
  end
end

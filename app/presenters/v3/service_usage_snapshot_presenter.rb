require 'presenters/v3/base_presenter'

module VCAP::CloudController
  module Presenters
    module V3
      class ServiceUsageSnapshotPresenter < BasePresenter
        def to_hash
          {
            guid: snapshot.guid,
            created_at: snapshot.created_at,
            completed_at: snapshot.completed_at,
            checkpoint_event_id: snapshot.checkpoint_event_id,
            checkpoint_event_created_at: snapshot.checkpoint_event_created_at,
            summary: {
              service_instance_count: snapshot.service_instance_count,
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
            self: { href: url_builder.build_url(path: "/v3/service_usage/snapshots/#{snapshot.guid}") },
            details: { href: url_builder.build_url(path: "/v3/service_usage/snapshots/#{snapshot.guid}/details") }
          }

          # Performance optimization: Only query for job link if snapshot is still processing.
          # Once a snapshot is complete, the job is no longer relevant to consumers - they
          # interact with the snapshot directly. This prevents N+1 queries when listing
          # many completed snapshots. For completed snapshots (the common case), we skip
          # the job lookup entirely, avoiding one database query per snapshot rendered.
          if snapshot.processing?
            pollable_job = PollableJobModel.where(
              resource_type: 'service_usage_snapshot',
              resource_guid: snapshot.guid
            ).first

            links[:job] = { href: url_builder.build_url(path: "/v3/jobs/#{pollable_job.guid}") } if pollable_job
          end

          if snapshot.checkpoint_event_id && snapshot.checkpoint_event_id > 0
            links[:checkpoint_event] = { href: url_builder.build_url(path: "/v3/service_usage_events/#{snapshot.checkpoint_event_id}") }
          end

          links
        end
      end
    end
  end
end

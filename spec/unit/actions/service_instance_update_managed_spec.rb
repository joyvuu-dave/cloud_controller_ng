require 'spec_helper'
require 'actions/service_instance_update_managed'

module VCAP::CloudController
  RSpec.describe ServiceInstanceUpdateManaged do
    describe '#update' do
      subject(:action) { described_class.new(event_repository) }

      let(:event_repository) do
        dbl = double(Repositories::ServiceEventRepository::WithUserActor)
        allow(dbl).to receive(:record_service_instance_event)
        allow(dbl).to receive(:user_audit_info)
        dbl
      end
      let(:message) { ServiceInstanceUpdateManagedMessage.new(body) }
      let!(:service_instance) do
        si = VCAP::CloudController::ManagedServiceInstance.make(
          name: 'foo',
          tags: %w(accounting mongodb)
        )
        si.label_ids = [
          VCAP::CloudController::ServiceInstanceLabelModel.make(key_prefix: 'pre.fix', key_name: 'to_delete', value: 'value'),
          VCAP::CloudController::ServiceInstanceLabelModel.make(key_prefix: 'pre.fix', key_name: 'tail', value: 'fluffy')
        ]
        si.annotation_ids = [
          VCAP::CloudController::ServiceInstanceAnnotationModel.make(key_prefix: 'pre.fix', key_name: 'to_delete', value: 'value').id,
          VCAP::CloudController::ServiceInstanceAnnotationModel.make(key_prefix: 'pre.fix', key_name: 'fox', value: 'bushy').id
        ]
        si
      end

      context 'when the new name is already taken' do
        let(:instance_in_same_space) { ServiceInstance.make(space: service_instance.space) }
        let(:body) { { name: instance_in_same_space.name } }

        it 'raises' do
          expect {
            action.update(service_instance, message)
          }.to raise_error CloudController::Errors::ApiError do |err|
            expect(err.name).to eq('ServiceInstanceNameTaken')
          end
        end
      end

      context 'when an operation is in progress' do
        let(:body) { {} }

        before do
          service_instance.save_with_new_operation({}, { type: 'delete', state: 'in progress' })
        end

        it 'raises' do
          expect {
            action.update(service_instance, message)
          }.to raise_error CloudController::Errors::ApiError do |err|
            expect(err.name).to eq('AsyncServiceInstanceOperationInProgress')
          end
        end
      end

      context 'when the update does not require communication with the broker' do
        let(:body) do
          {
            name: 'different-name',
            tags: %w(accounting couchbase nosql),
            metadata: {
              labels: {
                foo: 'bar',
                'pre.fix/to_delete': nil,
              },
              annotations: {
                alpha: 'beta',
                'pre.fix/to_delete': nil,
              }
            }
          }
        end

        it 'updates the values in the service instance in the database' do
          action.update(service_instance, message)

          service_instance.reload

          expect(service_instance.name).to eq('different-name')
          expect(service_instance.tags).to eq(%w(accounting couchbase nosql))
          expect(service_instance.labels.map { |l| { prefix: l.key_prefix, key: l.key_name, value: l.value } }).to match_array([
            { prefix: nil, key: 'foo', value: 'bar' },
            { prefix: 'pre.fix', key: 'tail', value: 'fluffy' },
          ])
          expect(service_instance.annotations.map { |a| { prefix: a.key_prefix, key: a.key, value: a.value } }).to match_array([
            { prefix: nil, key: 'alpha', value: 'beta' },
            { prefix: 'pre.fix', key: 'fox', value: 'bushy' },
          ])
        end

        it 'returns the updated service instance and a nil job' do
          si, job = action.update(service_instance, message)

          expect(si).to eq(service_instance.reload)
          expect(job).to be_nil
        end

        it 'creates an audit event' do
          action.update(service_instance, message)

          expect(event_repository).
            to have_received(:record_service_instance_event).with(
              :update,
              instance_of(ManagedServiceInstance),
              body.with_indifferent_access
            )
        end

        it 'updates the last operation' do
          lo = service_instance.last_operation

          si, _job = action.update(service_instance, message)

          expect(si.last_operation).not_to eq(lo)
          expect(si.last_operation.state).to eq('succeeded')
        end

        context 'when the update is empty' do
          let(:body) do
            {}
          end

          it 'succeeds' do
            action.update(service_instance, message)
          end
        end

        context 'SQL validation fails' do
          it 'raises an error and marks the update as failed' do
            errors = Sequel::Model::Errors.new
            errors.add(:blork, 'is busted')
            expect_any_instance_of(ManagedServiceInstance).to receive(:update).
              and_raise(Sequel::ValidationFailed.new(errors))

            expect { action.update(service_instance, message) }.
              to raise_error(ServiceInstanceUpdateManaged::InvalidServiceInstance, 'blork is busted')

            expect(service_instance.reload.last_operation.state).to eq('failed')
          end
        end
      end

      context 'when the update requires the broker' do
        let(:new_plan) { ServicePlan.make }
        let(:body) do
          {
            name: 'new-name',
            parameters: { foo: 'bar' },
            tags: %w(bar quz),
            relationships: {
              service_plan: {
                data: {
                  guid: new_plan.guid
                }
              }
            }
          }
        end

        describe 'fields that trigger broker interaction' do
          context 'parameters change requested' do
            let(:body) do
              {
                parameters: { foo: 'bar' },
              }
            end

            it 'should create a job' do
              _, job = action.update(service_instance, message)

              expect(job).to be_a(PollableJobModel)
              expect(job.operation).to eq('service_instance.update')
            end
          end

          context 'plan change requested' do
            let(:body) do
              {
                relationships: {
                  service_plan: {
                    data: {
                      guid: new_plan.guid
                    }
                  }
                }
              }
            end

            it 'should create a job' do
              _, job = action.update(service_instance, message)

              expect(job).to be_a(PollableJobModel)
              expect(job.operation).to eq('service_instance.update')
            end
          end

          context 'name change requested' do
            let!(:plan) { VCAP::CloudController::ServicePlan.make(service: offering) }
            let!(:service_instance) do
              VCAP::CloudController::ManagedServiceInstance.make(
                name: 'foo',
                service_plan: plan
              )
            end

            let(:body) do
              {
                name: 'new-different-name'
              }
            end

            context 'context update is allowed in the broker' do
              let!(:offering) do
                VCAP::CloudController::Service.make(allow_context_updates: true)
              end

              it 'should create a job' do
                _, job = action.update(service_instance, message)

                expect(job).to be_a(PollableJobModel)
                expect(job.operation).to eq('service_instance.update')
              end
            end

            context 'context update is not allowed in the broker' do
              let!(:offering) do
                VCAP::CloudController::Service.make(allow_context_updates: false)
              end

              it 'should not create a job' do
                _, job = action.update(service_instance, message)

                expect(job).to be_nil
              end
            end
          end
        end

        it 'locks the service instance' do
          action.update(service_instance, message)

          lo = service_instance.reload.last_operation
          expect(lo.type).to eq('update')
          expect(lo.state).to eq('in progress')
        end

        it 'does not update any attributes' do
          action.update(service_instance, message)

          service_instance.reload

          expect(service_instance.name).to eq('foo')
          expect(service_instance.tags).to eq(%w(accounting mongodb))
        end

        let!(:user_audit_info) { UserAuditInfo.new(user_email: 'test@example.com', user_guid: 'some-user') }

        context 'new UpdateServiceInstanceJob' do
          before do
            update_job = instance_double(V3::UpdateServiceInstanceJob)
            allow(V3::UpdateServiceInstanceJob).to receive(:new).and_return(update_job)

            enqueuer = instance_double(Jobs::Enqueuer, enqueue: nil, run_inline: nil)
            allow(Jobs::Enqueuer).to receive(:new).and_return(enqueuer)
            allow(enqueuer).to receive(:enqueue_pollable).
              and_return(PollableJobModel.make(resource_type: 'service_instance'))

            allow(event_repository).to receive(:user_audit_info).and_return(user_audit_info)
          end

          it 'creates an update job passing the right update fields' do
            action.update(service_instance, message)

            expect(V3::UpdateServiceInstanceJob).
              to have_received(:new).with(
                service_instance.guid,
                message: instance_of(ServiceInstanceUpdateManagedMessage),
                user_audit_info: instance_of(UserAuditInfo)
              )
          end
        end

        it 'returns a nil service instance and a job' do
          si, job = action.update(service_instance, message)

          expect(si).to be_nil
          expect(job).to be_a(PollableJobModel)
          expect(job.operation).to eq('service_instance.update')
        end

        it 'creates an audit event' do
          action.update(service_instance, message)

          expect(event_repository).
            to have_received(:record_service_instance_event).with(
              :start_update,
              instance_of(ManagedServiceInstance),
              body.with_indifferent_access
            )
        end
      end
    end
  end
end

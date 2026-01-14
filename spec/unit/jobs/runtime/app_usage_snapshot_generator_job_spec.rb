require 'spec_helper'
require 'jobs/runtime/usage_snapshot_generator_job'

module VCAP::CloudController
  module Jobs
    module Runtime
      RSpec.describe AppUsageSnapshotGeneratorJob do
        subject(:job) { AppUsageSnapshotGeneratorJob.new }

        let(:repository) { instance_double(Repositories::AppUsageSnapshotRepository) }

        before do
          allow(Repositories::AppUsageSnapshotRepository).to receive(:new).and_return(repository)
        end

        describe '#perform' do
          let(:snapshot) { AppUsageSnapshot.make(process_count: 100) }

          before do
            allow(repository).to receive(:generate_snapshot!).and_return(snapshot)
          end

          it 'calls the repository to generate a snapshot' do
            expect(repository).to receive(:generate_snapshot!)

            job.perform
          end

          it 'sets resource_guid to the generated snapshot guid' do
            job.perform

            expect(job.resource_guid).to eq(snapshot.guid)
          end

          it 'logs the start and completion' do
            logger = instance_double(Steno::Logger)
            allow(Steno).to receive(:logger).with('cc.background.app-usage-snapshot-generator').and_return(logger)

            expect(logger).to receive(:info).with('Starting usage snapshot generation')
            expect(logger).to receive(:info).with("Usage snapshot #{snapshot.guid} completed: 100 processes")

            job.perform
          end

          context 'when generation fails' do
            let(:error) { StandardError.new('Database connection failed') }

            before do
              allow(repository).to receive(:generate_snapshot!).and_raise(error)
            end

            it 'logs the error with backtrace' do
              logger = instance_double(Steno::Logger)
              allow(Steno).to receive(:logger).with('cc.background.app-usage-snapshot-generator').and_return(logger)

              expect(logger).to receive(:info).with('Starting usage snapshot generation')
              expect(logger).to receive(:error).with(/Usage snapshot generation failed: Database connection failed/)

              expect { job.perform }.to raise_error(StandardError, 'Database connection failed')
            end

            it 're-raises the error' do
              expect { job.perform }.to raise_error(StandardError, 'Database connection failed')
            end
          end
        end

        describe '#job_name_in_configuration' do
          it 'returns the correct job name' do
            expect(job.job_name_in_configuration).to eq(:app_usage_snapshot_generator)
          end
        end

        describe '#max_attempts' do
          it 'returns 1' do
            expect(job.max_attempts).to eq(1)
          end
        end

        describe '#resource_type' do
          it 'returns usage_snapshot' do
            expect(job.resource_type).to eq('app_usage_snapshot')
          end
        end

        describe '#display_name' do
          it 'returns the display name' do
            expect(job.display_name).to eq('app_usage_snapshot.generate')
          end
        end

        describe 'PollableJobWrapper integration' do
          let(:snapshot) { AppUsageSnapshot.make }

          before do
            allow(repository).to receive(:generate_snapshot!).and_return(snapshot)
          end

          it 'provides resource_guid for PollableJobModel linking' do
            expect(job.resource_guid).to be_nil

            job.perform

            expect(job.resource_guid).to eq(snapshot.guid)
            expect(job.resource_type).to eq('app_usage_snapshot')
          end
        end
      end
    end
  end
end

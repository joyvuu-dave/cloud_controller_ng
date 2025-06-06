require 'spec_helper'

module VCAP::CloudController
  RSpec.describe UploadBuildpack do
    let(:buildpack_blobstore) { double(:buildpack_blobstore).as_null_object }
    let!(:buildpack) { VCAP::CloudController::Buildpack.create_from_hash({ name: 'upload_binary_buildpack', stack: 'cider', position: 0 }) }

    let(:upload_buildpack) { UploadBuildpack.new(buildpack_blobstore) }

    let(:tmpdir) { Dir.mktmpdir }
    let(:filename) { 'file.zip' }
    let(:tgz_filename) { 'file.tgz' }
    let(:cnb_filename) { 'file.cnb' }

    let(:sha_valid_zip) { Digester.new(algorithm: OpenSSL::Digest::SHA256).digest_file(valid_zip) }
    let(:sha_valid_zip2) { Digester.new(algorithm: OpenSSL::Digest::SHA256).digest_file(valid_zip2) }
    let(:sha_valid_tgz) { Digester.new(algorithm: OpenSSL::Digest::SHA256).digest_file(valid_tgz) }
    let(:sha_valid_cnb) { Digester.new(algorithm: OpenSSL::Digest::SHA256).digest_file(valid_cnb) }

    let(:valid_zip_manifest_stack) { nil }
    let(:valid_zip) do
      zip_name = File.join(tmpdir, filename)
      TestZip.create(zip_name, 1, 1024) do |zipfile|
        if valid_zip_manifest_stack
          zipfile.get_output_stream('manifest.yml') do |f|
            f.write("---\nstack: #{valid_zip_manifest_stack}\n")
          end
        end
      end
      zip_file = File.new(zip_name)
      Rack::Test::UploadedFile.new(zip_file)
    end

    let(:valid_zip2) do
      zip_name = File.join(tmpdir, filename)
      TestZip.create(zip_name, 3, 1024)
      zip_file = File.new(zip_name)
      Rack::Test::UploadedFile.new(zip_file)
    end

    let(:valid_tgz) do
      tgz_name = File.join(tmpdir, tgz_filename)
      TestTgz.create(tgz_name, 3, 1024)
      tgz_file = File.new(tgz_name)
      Rack::Test::UploadedFile.new(tgz_file)
    end

    let(:valid_cnb) do
      cnb_name = File.join(tmpdir, cnb_filename)
      TestCnb.create(cnb_name, 3, 1024)
      cnb_file = File.new(cnb_name)
      Rack::Test::UploadedFile.new(cnb_file)
    end

    let(:staging_timeout) { TestConfig.config_instance.get(:staging, :timeout_in_seconds) }

    let(:expected_sha_valid_zip) { "#{buildpack.guid}_#{sha_valid_zip}" }

    context 'upload_buildpack' do
      before do
        allow(CloudController::DependencyLocator.instance).to receive(:buildpack_blobstore).and_return(buildpack_blobstore)
      end

      context 'and the upload to the blobstore succeeds' do
        context 'stack from manifest' do
          context 'manifest file is too large (>1mb)' do
            let(:valid_zip_manifest_stack) { 'cflinuxfs4' }
            let(:zip_with_massive_manifest) do
              zip_name = File.join(tmpdir, filename)
              TestZip.create(zip_name, 1, 1024) do |zipfile|
                if valid_zip_manifest_stack
                  zipfile.get_output_stream('manifest.yml') do |f|
                    alphachars = Array('A'..'Z')
                    megabyte_string = (0...(1024 * 1024)).map { alphachars.sample }.join
                    f.write("---\nstack: cflinuxfs4\nabsurdly_long_value: " + megabyte_string)
                  end
                end
              end
              zip_file = File.new(zip_name)
              Rack::Test::UploadedFile.new(zip_file)
            end

            it 'returns an error and does not update stack' do
              expect do
                upload_buildpack.upload_buildpack(buildpack, zip_with_massive_manifest, filename)
              end.to raise_error(CloudController::Errors::ApiError, /Buildpack zip error/)
              bp = Buildpack.find(name: buildpack.name)
              expect(bp).not_to be_nil
              expect(bp.stack).to eq('cider')
            end
          end

          context 'same as buildpack' do
            let(:valid_zip_manifest_stack) { 'cider' }

            it 'copies new bits to the blobstore' do
              expect(buildpack_blobstore).to receive(:cp_to_blobstore).with(valid_zip, expected_sha_valid_zip)

              upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)
            end
          end

          context 'different from buildpack' do
            let(:valid_zip_manifest_stack) { 'latkes' }

            before do
              VCAP::CloudController::Stack.create(name: valid_zip_manifest_stack)
            end

            it 'raises an error and does not update stack' do
              expect do
                upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)
              end.to raise_error(CloudController::Errors::ApiError, /Uploaded buildpack stack \(latkes\) does not match cider/)
              bp = Buildpack.find(name: buildpack.name)
              expect(bp).not_to be_nil
              expect(bp.stack).to eq('cider')
            end
          end

          context 'stack previously unknown' do
            let!(:buildpack) { VCAP::CloudController::Buildpack.create_from_hash({ name: 'upload_binary_buildpack', stack: nil, position: 0 }) }

            context 'and the stack exists' do
              let(:valid_zip_manifest_stack) { 'cflinuxfs4_new' }

              before do
                VCAP::CloudController::Stack.create(name: valid_zip_manifest_stack)
              end

              it 'copies new bits to the blobstore and updates the stack' do
                expect(buildpack_blobstore).to receive(:cp_to_blobstore).with(valid_zip, expected_sha_valid_zip)

                expect do
                  upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)
                end.to change(buildpack, :stack).from(nil).to(valid_zip_manifest_stack)
              end

              context 'buildpack with same name and stack exists' do
                it 'raises an error' do
                  VCAP::CloudController::Buildpack.create(name: buildpack.name, stack: valid_zip_manifest_stack)
                  expect do
                    upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)
                  end.to raise_error(CloudController::Errors::ApiError,
                                     /The buildpack name #{buildpack.name} is already in use for the stack #{valid_zip_manifest_stack} and the lifecycle #{buildpack.lifecycle}/)
                end
              end
            end

            context "but the stack doesn't exist" do
              let(:valid_zip_manifest_stack) { 'new-and-unknown' }

              it 'raises an error' do
                expect do
                  upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)
                end.to raise_error(CloudController::Errors::ApiError, /Uploaded buildpack stack \(#{valid_zip_manifest_stack}\) does not exist/)
                bp = Buildpack.find(name: buildpack.name)
                expect(bp).not_to be_nil
                expect(bp.filename).to be_nil
              end
            end
          end
        end

        context 'lifecycle: gzip cnb' do
          let!(:buildpack) { VCAP::CloudController::Buildpack.create_from_hash({ name: 'upload_cnb_buildpack', stack: 'cider', position: 0, lifecycle: 'cnb' }) }
          let(:expected_sha_valid_tgz) { "#{buildpack.guid}_#{sha_valid_tgz}" }

          it 'uploads' do
            expect(buildpack_blobstore).to receive(:cp_to_blobstore).with(valid_tgz, expected_sha_valid_tgz)

            upload_buildpack.upload_buildpack(buildpack, valid_tgz, tgz_filename)
          end
        end

        context 'lifecycle: cnb' do
          let!(:buildpack) { VCAP::CloudController::Buildpack.create_from_hash({ name: 'upload_cnb_buildpack', stack: 'cider', position: 0, lifecycle: 'cnb' }) }
          let(:expected_sha_valid_cnb) { "#{buildpack.guid}_#{sha_valid_cnb}" }

          it 'uploads' do
            expect(buildpack_blobstore).to receive(:cp_to_blobstore).with(valid_cnb, expected_sha_valid_cnb)

            upload_buildpack.upload_buildpack(buildpack, valid_cnb, cnb_filename)
          end
        end

        it 'updates the buildpack filename' do
          expect do
            upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)
          end.to change {
            Buildpack.find(name: 'upload_binary_buildpack').filename
          }.from(nil).to(filename)
        end

        context 'new bits (new sha)' do
          it 'copies new bits to the blobstore and updates the key and checksum' do
            expect(buildpack_blobstore).to receive(:cp_to_blobstore).with(valid_zip, expected_sha_valid_zip)

            expect(buildpack.key).to be_nil
            expect(buildpack.sha256_checksum).to be_nil

            upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)

            expect(buildpack.key).to eq(expected_sha_valid_zip)
            expect(buildpack.sha256_checksum).to eq(sha_valid_zip)
          end

          it 'does not attempt to delete the old buildpack blob when it does not exist' do
            expect(VCAP::CloudController::BuildpackBitsDelete).not_to receive(:delete_when_safe)
            upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)
          end

          context 'when there is an old buildpack in the blobstore' do
            before { buildpack.update(key: 'existing_key') }

            it 'removes the old buildpack binary when a new one is uploaded' do
              allow(VCAP::CloudController::BuildpackBitsDelete).to receive(:delete_when_safe)
              upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)
              expect(VCAP::CloudController::BuildpackBitsDelete).to have_received(:delete_when_safe).with('existing_key', staging_timeout)
            end
          end

          context 'when two upload_buildpack calls are running at the same time' do
            it 'does not delete the buildpack' do
              expect(buildpack_blobstore).to receive(:cp_to_blobstore) do
                Buildpack.find(name: 'upload_binary_buildpack').update(key: expected_sha_valid_zip)
              end

              expect(VCAP::CloudController::BuildpackBitsDelete).not_to receive(:delete_when_safe)
              expect(upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)).to be true
            end
          end
        end

        context 'same bits (same sha)' do
          before do
            buildpack.update(key: expected_sha_valid_zip, filename: filename)
          end

          context 'when bits provided are already in the blobstore' do
            before do
              allow(buildpack_blobstore).to receive(:exists?).with(expected_sha_valid_zip).and_return(true)
            end

            it 'does not copy bits to the blobstore if nothing has changed' do
              expect(buildpack_blobstore).not_to receive(:cp_to_blobstore)
              expect(VCAP::CloudController::BuildpackBitsDelete).not_to receive(:delete_when_safe)
              expect(upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)).to be false
            end
          end

          context 'when the bit are missing from the blobstore' do
            before do
              allow(buildpack_blobstore).to receive(:exists?).with(expected_sha_valid_zip).and_return(false)
            end

            it 'returns true if the bits are uploaded and does not remove the bits' do
              expect(buildpack_blobstore).to receive(:cp_to_blobstore)
              expect(VCAP::CloudController::BuildpackBitsDelete).not_to receive(:delete_when_safe)
              expect(upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)).to be true
            end
          end
        end

        context 'when the same bits are uploaded twice' do
          let(:buildpack2) { VCAP::CloudController::Buildpack.create_from_hash({ name: 'buildpack2', stack: 'cflinuxfs4', position: 0 }) }

          it 'has different keys' do
            upload_buildpack.upload_buildpack(buildpack, valid_zip2, filename)
            upload_buildpack.upload_buildpack(buildpack2, valid_zip2, filename)
            bp1 = Buildpack.find(name: 'upload_binary_buildpack')
            bp2 = Buildpack.find(name: 'buildpack2')
            expect(bp1.key).not_to eq(bp2.key)
          end
        end
      end

      context 'and the upload to the blobstore fails' do
        let(:previous_key) { 'previous_key' }
        let(:previous_filename) { 'previous_filename' }

        before do
          allow(buildpack_blobstore).to receive(:cp_to_blobstore).and_raise
          buildpack.update(key: previous_key, filename: previous_filename)
        end

        it 'does not update the key and filename on the existing buildpack' do
          expect { upload_buildpack.upload_buildpack(buildpack, valid_zip, filename) }.to raise_error(RuntimeError)
          bp = Buildpack.find(name: buildpack.name)
          expect(bp).not_to be_nil
          expect(bp.key).to eq(previous_key)
          expect(bp.filename).to eq(previous_filename)
        end
      end

      context 'when updating the buildpack fails' do
        before do
          allow(buildpack_blobstore).to receive(:cp_to_blobstore) do
            buildpack.delete
          end
        end

        it 'deletes the uploaded blob from the blobstore' do
          allow(VCAP::CloudController::BuildpackBitsDelete).to receive(:delete_when_safe)

          upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)
          expect(BuildpackBitsDelete).to have_received(:delete_when_safe).with(expected_sha_valid_zip, 0)
        end
      end

      context 'when the buildpack is locked' do
        before { buildpack.update(locked: true) }

        it 'does nothing' do
          expect(buildpack_blobstore).not_to receive(:cp_to_blobstore)
          expect(upload_buildpack.upload_buildpack(buildpack, valid_zip, filename)).to be false
        end
      end
    end
  end
end

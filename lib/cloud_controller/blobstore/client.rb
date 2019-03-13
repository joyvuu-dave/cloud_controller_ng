require 'cloud_controller/blobstore/blob'

module CloudController
  module Blobstore
    class Client
      extend Forwardable

      attr_reader :wrapped_client

      def initialize(client)
        @wrapped_client = client
      end

      def_delegators :@wrapped_client,
        :local?,
        :exists?,
        :download_from_blobstore,
        :cp_to_blobstore,
        :cp_r_to_blobstore,
        :cp_file_between_keys,
        :delete_all,
        :delete_all_in_path,
        :delete,
        :delete_blob,
        :download_uri,
        :blob,
        :files_for,
        :root_dir,
        # TODO what should we do about some methods only being used for bits?
        :get_buildpack_metadata,
        :public_upload_url
    end
  end
end

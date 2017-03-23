# encoding: utf-8

require "carrierwave"
require "carrierwave/storage/fog"
require "carrierwave/storage/file"
require "carrierwave/uploader"

module CarrierWave
  module Workers

    module StoreAssetMixin
      include CarrierWave::Workers::Base

      def self.included(base)
        base.extend CarrierWave::Workers::ClassMethods
      end

      attr_reader :cache_path, :tmp_directory

      def perform(*args)
        record = super(*args)

        if record && record.send(:"#{column}_tmp")
          store_directories(record)
          record.send :"process_#{column}_upload=", true
          record.send :"#{column}_tmp=", nil
          record.send :"#{column}_processing=", false if record.respond_to?(:"#{column}_processing")
          open(cache_path) { |f| record.send :"#{column}=", f }
          if record.save!
            if is_fog?
              require "aws-sdk"
              credential_keys = CarrierWave::Uploader::Base.fog_credentials
              bucket_name = CarrierWave::Workers::Base.fog_directory
              client = AWS::S3::Client.new(
                          region:            credential_keys[:region],
                          access_key_id:     credential_keys[:aws_access_key_id],
                          secret_access_key: credential_keys[:aws_secret_access_key]
                        )
              client.delete_object(bucket: bucket_name, key: @tmp_directory)
            else
              FileUtils.rm_r(tmp_directory, :force => true)
            end
          end
        else
          when_not_ready
        end
      end

      private

      def store_directories(record)
        asset, asset_tmp = record.send(:"#{column}"), record.send(:"#{column}_tmp")
        if is_fog?
          cache_url = "#{CarrierWave::Uploader::Base.fog_directory}.s3.amazonaws.com"
          @cache_path = "#{cache_url}/#{asset.cache_dir}/#{asset_tmp}"
          @tmp_directory = "#{asset.cache_dir}/#{asset_tmp}"
        else
          cache_directory  = File.expand_path(asset.cache_dir, asset.root)
          @cache_path      = File.join(cache_directory, asset_tmp)
          @tmp_directory   = File.join(cache_directory, asset_tmp.split("/").first)
        end
      end

      def is_fog?
        if CarrierWave::Uploader::Base.cache_storage == CarrierWave::Storage::Fog
          true
        elsif CarrierWave::Uploader::Base.cache_storage == CarrierWave::Storage::File
          false
        end
      end

    end # StoreAssetMixin

  end # Workers
end # Backgrounder

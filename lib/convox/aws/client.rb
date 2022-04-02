# frozen_string_literal: true

require 'logger'
require 'json'
require 'fileutils'
require 'rubygems'
require 'os'

module Convox
  module AWS
    class Client
      attr_accessor :logger, :config

      def initialize(options = {})
        @logger = options[:logger]
        unless @logger
          @logger = Logger.new($stdout)
          @logger.level = options[:log_level] || Logger::INFO
        end
        @config = options[:config] || {}
      end

      def s3_bucket_exists?(name)
        access_key_id = config.fetch(:aws_access_key_id)
        secret_access_key = config.fetch(:aws_secret_access_key)

        logger.debug "Searching for existing S3 bucket #{name}..."
        command = "AWS_ACCESS_KEY_ID=#{access_key_id} " \
                  "AWS_SECRET_ACCESS_KEY=#{secret_access_key} " \
                  "aws s3api list-buckets --query 'Buckets[?Name==`#{name}`]' --output text"
        bucket_acl_output = `#{command}`.strip

        # Empty string means the bucket doesn't exist yet
        bucket_exists = bucket_acl_output != ''

        if bucket_exists
          logger.debug 'Found existing S3 bucket.'
        else
          logger.debug 'S3 bucket does not exist.'
        end

        bucket_exists
      end

      def create_s3_bucket!(name, check_if_exists: true)
        return if check_if_exists && s3_bucket_exists?(name)

        logger.info "Creating S3 bucket #{bucket_name}..."
        run_aws_command! "s3api create-bucket --bucket '#{name}' --region #{config.fetch(:aws_region)}"
      end

      def run_aws_command!(cmd, env = {})
        access_key_id = config.fetch(:aws_access_key_id)
        secret_access_key = config.fetch(:aws_secret_access_key)

        command = "AWS_ACCESS_KEY_ID=#{access_key_id} " \
                  "AWS_SECRET_ACCESS_KEY=#{secret_access_key} " \
                  "aws #{cmd}"
        logger.debug "+ #{command}"
        system env, command
        raise "Error running: #{command}" unless $CHILD_STATUS.success?
      end
    end
  end
end

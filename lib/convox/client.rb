# frozen_string_literal: true

require "logger"
require "json"
require "fileutils"

module Convox
  class Client
    CONVOX_DIR = File.expand_path("~/.convox").freeze
    AUTH_FILE = File.join(CONVOX_DIR, "auth")
    HOST_FILE = File.join(CONVOX_DIR, "host")

    attr_accessor :logger, :config

    def auth
      @auth ||= load_auth_from_file
    end

    def initialize(options = {})
      @logger = Logger.new(STDOUT)
      logger.level = options[:log_level] || Logger::INFO
      @config = options[:config] || {}
    end

    def backup_convox_host_and_rack
      %w[host rack].each do |f|
        path = File.join(CONVOX_DIR, f)
        if File.exist?(path)
          bak_file = "#{path}.bak"
          logger.info "Moving existing #{path} to #{bak_file}..."
          FileUtils.mv(path, bak_file)
        end
      end
    end

    def install_convox
      require_config(%i[
        aws_region
        aws_access_key_id
        aws_secret_access_key
        stack_name
        instance_type
      ])

      logger.info "Installing Convox (#{config.fetch(:stack_name)})..."

      env = {
        "AWS_REGION" => config.fetch(:aws_region),
        "AWS_ACCESS_KEY_ID" => config.fetch(:aws_access_key_id),
        "AWS_SECRET_ACCESS_KEY" => config.fetch(:aws_secret_access_key),
      }
      command = %Q{convox rack install aws \
--name "#{config.fetch(:stack_name)}" \
"InstanceType=#{config.fetch(:instance_type)}" \
"BuildInstance="}
      run_command(command, env)
    end

    def validate_convox_auth_and_set_host!
      require_config(%i[ aws_region stack_name ])

      unless File.exist?(AUTH_FILE)
        raise "Could not find auth file at #{AUTH_FILE}!"
      end

      region = config.fetch(:aws_region)
      stack = config.fetch(:stack_name)

      match_count = 0
      matching_host = nil
      auth.each do |host, password|
        if host.match?(/^#{stack}-\d+\.#{region}\.elb\.amazonaws\.com$/)
          matching_host = host
          match_count += 1
        end
      end

      if match_count == 1
        set_host(matching_host)
        return matching_host
      end

      if match_count > 1
        error_message = "Found multiple matching hosts for "
      else
        error_message = "Could not find matching authentication for "
      end
      error_message += "region: #{region}, stack: #{stack}"
      raise error_message
    end

    def set_host(host)
      File.open(HOST_FILE, "w") { |f| f.puts host }
    end

    private

    def run_command(cmd, env = {})
      puts env.inspect
      puts command

      # system(env, command)
    end

    def load_auth_from_file
      return {} unless File.exist?(AUTH_FILE)

      JSON.parse(File.read(AUTH_FILE))
    end

    def require_config(required_keys)
      required_keys.each do |k|
        raise "#{k} is missing from the config!" unless config[k]
      end
    end
  end
end

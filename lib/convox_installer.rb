# frozen_string_literal: true

require "active_support"
require "active_support/core_ext"
require "convox_installer/config"
require "convox_installer/requirements"
require "convox"

module ConvoxInstaller
  def client
    @client ||= Convox::Client.new(log_level: @log_level, config: config.config)
  end

  def config
    options = {log_level: @log_level}
    options[:prompts] = @prompts if @prompts
    @config ||= Config.new(options)
  end

  def requirements
    @requirements ||= Requirements.new(log_level: @log_level)
  end

  def ensure_requirements!
    requirements.ensure_requirements!
  end

  def prompt_for_config
    config.prompt_for_config
  end

  %w[
    backup_convox_host_and_rack
    install_convox
    validate_convox_auth_and_set_host!
    validate_convox_rack!
    create_convox_app!
    set_default_app_for_directory!
    create_s3_bucket!
    add_docker_registry!
    s3_bucket_details
    convox_rack_data
    default_service_domain_name
    run_convox_command!
  ].each do |method|
    define_method(method) do |*args|
      client.send(method, *args)
    end
  end
end

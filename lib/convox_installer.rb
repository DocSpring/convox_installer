# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext'
require 'convox_installer/config'
require 'convox_installer/requirements'
require 'convox'

module ConvoxInstaller
  def client
    @client ||= Convox::Client.new(log_level: @log_level, config: config.config)
  end

  def config
    options = { log_level: @log_level }
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
    validate_convox_rack_and_write_current!
    validate_convox_rack_api!
    convox_rack_data
    create_convox_app!
    set_default_app_for_directory!
    add_s3_bucket
    add_rds_database
    add_elasticache_cluster
    apply_terraform_update!
    terraform_state
    s3_bucket_details
    elasticache_details
    rds_details
    add_docker_registry!
    default_service_domain_name
    run_convox_command!
    logger
    rack_already_installed?
  ].each do |method|
    define_method(method) do |*args|
      client.send(method, *args)
    end
  end
end

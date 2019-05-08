# frozen_string_literal: true

require "active_support"
require "active_support/core_ext"
require "convox_installer/config"
require "convox_installer/requirements"

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

  def ensure_requirements
    requirements.ensure_requirements
  end

  def prompt_for_config
    config.prompt_for_config
  end

  def backup_convox_host_and_rack
    client.backup_convox_host_and_rack
  end

  def install_convox
    client.install
  end
end

# frozen_string_literal: true

require "active_support"
require "active_support/core_ext"
require "convox_installer/config"
require "convox_installer/requirements"

module ConvoxInstaller
  def client
    @client ||= Convox::Client.new(log_level: @log_level)
  end

  def ensure_requirements!
    @requirements = Requirements.new(log_level: @log_level)
    @requirements.ensure_requirements!
  end

  def prompt_for_config(options = {})
    @config = Config.new({log_level: @log_level}.merge(options))
    @config.prompt_for_config
    @config.config
  end

  def backup_convox_config
    client.backup_convox_config
  end
end

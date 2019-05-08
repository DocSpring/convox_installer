# frozen_string_literal: true

require "logger"
require "json"
require "fileutils"

module Convox
  class Client
    CONVOX_DIR = File.expand_path("~/.convox").freeze
    AUTH_FILE = File.join(CONVOX_DIR, "auth")

    attr_accessor :logger

    def auth
      @auth ||= load_auth_from_file
    end

    def initialize(options = {})
      @logger = Logger.new(STDOUT)
      logger.level = options[:log_level] || Logger::INFO
    end

    def backup_convox_config!
      %w[host rack].each do |f|
        path = File.join(CONVOX_DIR, f)
        if File.exist?(path)
          bak_file = "#{path}.bak"
          logger.info "Moving existing #{path} to #{bak_file}..."
          FileUtils.mv(path, bak_file)
        end
      end
    end

    private

    def load_auth_from_file
      return {} unless File.exist?(AUTH_FILE)

      JSON.parse(File.read(AUTH_FILE))
    end
  end
end

# frozen_string_literal: true

require "highline"
require "os"
require "logger"

module ConvoxInstaller
  class Requirements
    attr_accessor :ecr_label, :logger

    def initialize(options = {})
      @ecr_label = options[:ecr_label]
      @logger = Logger.new(STDOUT)
      logger.level = options[:log_level] || Logger::INFO
    end

    def ensure_requirements
      logger.debug "Checking for required commands..."

      @missing_packages = []
      unless has_command? "convox"
        @missing_packages << {
          name: "convox",
          brew: "convox",
          docs: "https://docs.convox.com/introduction/installation",
        }
      end

      unless has_command? "aws"
        @missing_packages << {
          name: "aws",
          brew: "awscli",
          docs: "https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html",
        }
      end

      if @missing_packages.any?
        logger.error "This script requires the convox and AWS CLI tools."
        if OS.mac?
          logger.error "Please run: brew install " \
                       "#{@missing_packages.map { |p| p[:brew] }.join(" ")}"
        else
          logger.error "Installation Instructions:"
          @missing_packages.each do |package|
            logger.error "* #{package[:name]}: #{package[:docs]}"
          end
        end
        quit!
      end
    end

    def has_command?(command)
      path = find_command command
      if path.present?
        logger.debug "=> Found #{command}: #{path}"
        return true
      end
      logger.debug "=> Could not find #{command}!"
      false
    end

    # Stubbed in tests
    def find_command(command)
      `which #{command} 2>/dev/null`.chomp
    end

    def quit!
      exit 1
    end
  end
end

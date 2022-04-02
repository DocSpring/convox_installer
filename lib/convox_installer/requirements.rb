# frozen_string_literal: true

require 'highline'
require 'os'
require 'logger'

module ConvoxInstaller
  class Requirements
    attr_accessor :ecr_label, :logger

    def initialize(options = {})
      @ecr_label = options[:ecr_label]
      @logger = Logger.new($stdout)
      logger.level = options[:log_level] || Logger::INFO
    end

    def ensure_requirements!
      logger.debug 'Checking for required commands...'

      @missing_packages = []
      unless command_present? 'convox'
        @missing_packages << {
          name: 'convox',
          brew: 'convox',
          docs: 'https://docs.convox.com/introduction/installation'
        }
      end

      unless command_present? 'aws'
        @missing_packages << {
          name: 'aws',
          brew: 'awscli',
          docs: 'https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html'
        }
      end

      if @missing_packages.any?
        logger.error 'This script requires the convox and AWS CLI tools.'
        if OS.mac?
          logger.error 'Please run: brew install ' \
                       "#{@missing_packages.map { |p| p[:brew] }.join(' ')}"
        else
          logger.error 'Installation Instructions:'
          @missing_packages.each do |package|
            logger.error "* #{package[:name]}: #{package[:docs]}"
          end
        end
        quit!
      end

      client = Convox::Client.new
      return if client.convox_3_cli?

      logger.error 'This script requires Convox CLI version 3.x.x. ' \
                   "Your Convox CLI version is: #{client.cli_version_string}"
      logger.error "Please run 'brew update convox' or follow the instructions " \
                   'at https://docs.convox.com/getting-started/introduction'
      quit!
    end

    def command_present?(command)
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

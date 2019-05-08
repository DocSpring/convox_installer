# frozen_string_literal: true

require "highline"
require "fileutils"
require "json"
require "securerandom"

module ConvoxInstaller
  class Config
    attr_accessor :logger, :config, :prompts, :highline

    CONFIG_FILE = File.expand_path("~/.convox/installer_config").freeze

    DEFAULT_PROMPTS = [
      {
        key: :stack_name,
        title: "Convox Stack Name",
        prompt: "Please enter a name for your Convox installation",
        default: "convox",
      },
      {
        key: :aws_region,
        title: "AWS Region",
        default: "us-east-1",
      },
      {
        key: :instance_type,
        title: "EC2 Instance Type",
        default: "t3.medium",
      },
      {
        section: "Admin AWS Credentials",
      },
      {
        key: :aws_access_key_id,
        title: "AWS Access Key ID",
      },
      {
        key: :aws_secret_access_key,
        title: "AWS Secret Access Key",
      },
    ].freeze

    def initialize(options = {})
      @logger = Logger.new(STDOUT)
      logger.level = options[:log_level] || Logger::INFO

      self.prompts = options[:prompts] || DEFAULT_PROMPTS
      self.config = {}
      load_config_from_file
      load_config_from_env
      self.config = config.merge((options[:config] || {}).symbolize_keys)

      self.highline = options[:highline] || HighLine.new
    end

    def config_keys
      prompts.map { |prompt| prompt[:key] }.compact.map(&:to_sym)
    end

    def prompt_for_config
      loop do
        prompts.each do |prompt|
          if prompt[:section]
            highline.say "\n#{prompt[:section]}"
            highline.say "============================================\n\n"
          end
          next unless prompt[:key]

          ask_prompt(prompt)
        end

        show_config_summary

        @completed_prompt = true

        highline.say "Please double check all of these configuration details."

        agree = highline.agree(
          "Would you like to start the Convox installation?" \
          " (press 'n' to correct any settings)"
        )
        break if agree
        highline.say "\n"
      end

      config
    end

    def show_config_summary
      highline.say "\n============================================"
      highline.say "                 SUMMARY"
      highline.say "============================================\n\n"

      config_titles = prompts.map do |prompt|
        prompt[:title] || prompt[:key]
      end.compact
      max = config_titles.map(&:length).max

      prompts.each do |prompt|
        next if !prompt[:key] || prompt[:hidden]

        value = config[prompt[:key]]
        title = prompt[:title] || prompt[:key]
        padded_key = "#{title}:".ljust(max + 3)
        highline.say "    #{padded_key} #{value}"
      end
      highline.say "\nWe've saved your configuration to: #{CONFIG_FILE}"
      highline.say "If anything goes wrong during the installation, " \
                   "you can restart the script to reload the config and continue.\n\n"
    end

    private

    def ask_prompt(prompt)
      key = prompt[:key]
      title = prompt[:title] || key

      # If looping through the config again, ask for all
      # the config with defaults.
      if config[key] && !@completed_prompt
        logger.debug "Found existing config for #{key} => #{config[key]}"
        return
      end

      # Used when we want to force a default value and not prompt the user.
      # (e.g. securely generated passwords)
      if prompt[:value]
        return if config[key]

        default = prompt[:value]
        config[key] = default.is_a?(Proc) ? default.call : default
        save_config_to_file
        return
      end

      prompt_string = prompt[:prompt] || "Please enter your #{title}: "

      config[key] = highline.ask(prompt_string) do |q|
        if @completed_prompt
          q.default = config[key]
        elsif prompt[:default]
          q.default = prompt[:default]
        end
        q.validate = /.+/
      end

      save_config_to_file
    end

    def load_config_from_file
      return unless Config.config_file_exists?

      logger.debug "Loading saved config from #{CONFIG_FILE}..."

      loaded_config = JSON.parse(Config.read_config_file)["config"].symbolize_keys
      self.config = config.merge(loaded_config).slice(*config_keys)
    end

    def load_config_from_env
      config_keys.each do |key|
        env_key = key.to_s.upcase
        value = ENV[env_key]
        next unless value.present?

        logger.debug "Found value for #{key} in env var: #{env_key} => #{value}"
        config[key] = value
      end
    end

    def save_config_to_file
      FileUtils.mkdir_p File.expand_path("~/.convox")
      File.open(CONFIG_FILE, "w") do |f|
        f.puts({config: config}.to_json)
      end
    end

    def self.config_file_exists?
      File.exist?(CONFIG_FILE)
    end

    def self.read_config_file
      File.read(CONFIG_FILE)
    end
  end
end

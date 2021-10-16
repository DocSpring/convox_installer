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
      load_auth_from_file
    end

    def initialize(options = {})
      @logger = Logger.new(STDOUT)
      logger.level = options[:log_level] || Logger::INFO
      @config = options[:config] || {}
    end

    def backup_convox_host_and_rack
      FileUtils.mkdir_p CONVOX_DIR

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
      require_config(%i[ aws_region stack_name ])
      region = config.fetch(:aws_region)
      stack_name = config.fetch(:stack_name)

      if rack_already_installed?
        logger.info "There is already a Convox stack named #{stack_name} " \
                    "in the #{region} AWS region. Using this rack. "
        return true
      end

      require_config(%i[
        aws_region
        aws_access_key_id
        aws_secret_access_key
        stack_name
        instance_type
      ])

      logger.info "Installing Convox (#{stack_name})..."

      env = {
        "AWS_REGION" => region,
        "AWS_ACCESS_KEY_ID" => config.fetch(:aws_access_key_id),
        "AWS_SECRET_ACCESS_KEY" => config.fetch(:aws_secret_access_key),
      }
      command = %Q{rack install aws \
--name "#{config.fetch(:stack_name)}" \
"InstanceType=#{config.fetch(:instance_type)}" \
"BuildInstance="}

      run_convox_command!(command, env)
    end

    def rack_already_installed?
      require_config(%i[ aws_region stack_name ])

      return unless File.exist?(AUTH_FILE)

      region = config.fetch(:aws_region)
      stack_name = config.fetch(:stack_name)

      auth.each do |host, password|
        if host.match?(/^#{stack_name}-\d+\.#{region}\.elb\.amazonaws\.com$/)
          return true
        end
      end
      false
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
      logger.debug "Setting convox host to #{host} (in #{HOST_FILE})..."
      File.open(HOST_FILE, "w") { |f| f.puts host }
    end

    def validate_convox_rack!
      require_config(%i[
        aws_region
        stack_name
        instance_type
      ])
      logger.debug "Validating that convox rack has the correct attributes..."
      {
        provider: "aws",
        region: config.fetch(:aws_region),
        type: config.fetch(:instance_type),
        name: config.fetch(:stack_name),
      }.each do |k, v|
        convox_value = convox_rack_data[k.to_s]
        if convox_value != v
          raise "Convox data did not match! Expected #{k} to be '#{v}', " \
                "but was: '#{convox_value}'"
        end
      end
      logger.debug "=> Convox rack has the correct attributes."
      true
    end

    def convox_rack_data
      @convox_rack_data ||= begin
        logger.debug "Fetching convox rack attributes..."
        convox_output = `convox api get /system`
        raise "convox command failed!" unless $?.success?
        JSON.parse(convox_output)
      end
    end

    def create_convox_app!
      require_config(%i[convox_app_name])
      return true if convox_app_exists?

      app_name = config.fetch(:convox_app_name)

      logger.info "Creating app: #{app_name}..."
      logger.info "=> Documentation: " \
                  "https://docs.convox.com/deployment/creating-an-application"

      run_convox_command! "apps create #{app_name} --wait"

      retries = 0
      loop do
        break if convox_app_exists?
        if retries > 5
          raise "Something went wrong while creating the #{app_name} app! " \
                "(Please wait a few moments and then restart the installation script.)"
        end
        logger.info "Waiting for #{app_name} to be ready..."
        sleep 3
        retries += 1
      end

      logger.info "=> #{app_name} app created!"
    end

    def set_default_app_for_directory!
      logger.info "Setting default app in ./.convox/app..."
      FileUtils.mkdir_p File.expand_path("./.convox")
      File.open(File.expand_path("./.convox/app"), "w") do |f|
        f.puts config.fetch(:convox_app_name)
      end
    end

    def convox_app_exists?
      require_config(%i[convox_app_name])
      app_name = config.fetch(:convox_app_name)

      logger.debug "Looking for existing #{app_name} app..."
      convox_output = `convox api get /apps`
      raise "convox command failed!" unless $?.success?

      apps = JSON.parse(convox_output)
      apps.each do |app|
        if app["name"] == app_name
          logger.debug "=> Found #{app_name} app."
          return true
        end
      end
      logger.debug "=> Did not find #{app_name} app."
      false
    end

    # Create the s3 bucket, and also apply a CORS configuration
    def create_s3_bucket!
      require_config(%i[s3_bucket_name])
      bucket_name = config.fetch(:s3_bucket_name)
      if s3_bucket_exists?
        logger.info "#{bucket_name} S3 bucket already exists!"
      else
        logger.info "Creating S3 bucket resource (#{bucket_name})..."
        run_convox_command! "rack resources create s3 " \
                            "--name \"#{bucket_name}\" " \
                            "--wait"

        retries = 0
        loop do
          break if s3_bucket_exists?

          if retries > 10
            raise "Something went wrong while creating the #{bucket_name} S3 bucket! " \
                  "(Please wait a few moments and then restart the installation script.)"
          end
          logger.debug "Waiting for S3 bucket to be ready..."
          sleep 3
          retries += 1
        end

        logger.debug "=> S3 bucket created!"
      end

      set_s3_bucket_cors_policy
    end

    def s3_bucket_exists?
      require_config(%i[s3_bucket_name])
      bucket_name = config.fetch(:s3_bucket_name)
      logger.debug "Looking up S3 bucket resource: #{bucket_name}"
      `convox api get /resources/#{bucket_name} 2>/dev/null`
      $?.success?
    end

    def s3_bucket_details
      require_config(%i[s3_bucket_name])
      @s3_bucket_details ||= begin
        bucket_name = config.fetch(:s3_bucket_name)
        logger.debug "Fetching S3 bucket resource details for #{bucket_name}..."

        response = `convox api get /resources/#{bucket_name}`
        raise "convox command failed!" unless $?.success?

        bucket_data = JSON.parse(response)
        s3_url = bucket_data["url"]
        matches = s3_url.match(
          /^s3:\/\/(?<access_key_id>[^:]*):(?<secret_access_key>[^@]*)@(?<bucket_name>.*)$/
        )

        match_keys = %i[access_key_id secret_access_key bucket_name]
        unless matches && match_keys.all? { |k| matches[k].present? }
          raise "#{s3_url} is an invalid S3 URL!"
        end

        {
          access_key_id: matches[:access_key_id],
          secret_access_key: matches[:secret_access_key],
          name: matches[:bucket_name],
        }
      end
    end

    def set_s3_bucket_cors_policy
      require_config(%i[aws_access_key_id aws_secret_access_key])
      access_key_id = config.fetch(:aws_access_key_id)
      secret_access_key = config.fetch(:aws_secret_access_key)

      unless config.key? :s3_bucket_cors_policy
        logger.debug "No CORS policy provided in config: s3_bucket_cors_policy"
        return
      end
      cors_policy_string = config.fetch(:s3_bucket_cors_policy)

      bucket_name = s3_bucket_details[:name]

      logger.debug "Looking up existing CORS policy for #{bucket_name}"
      existing_cors_policy_string =
        `AWS_ACCESS_KEY_ID=#{access_key_id} \
        AWS_SECRET_ACCESS_KEY=#{secret_access_key} \
        aws s3api get-bucket-cors --bucket #{bucket_name} 2>/dev/null`
      if $?.success? && existing_cors_policy_string.present?
        # Sort all the nested arrays so that the equality operator works
        existing_cors_policy = JSON.parse(existing_cors_policy_string)
        cors_policy_json = JSON.parse(cors_policy_string)
        [existing_cors_policy, cors_policy_json].each do |policy_json|
          if policy_json.is_a?(Hash) && policy_json["CORSRules"]
            policy_json["CORSRules"].each do |rule|
              rule["AllowedHeaders"].sort! if rule["AllowedHeaders"]
              rule["AllowedMethods"].sort! if rule["AllowedMethods"]
              rule["AllowedOrigins"].sort! if rule["AllowedOrigins"]
            end
          end
        end

        if existing_cors_policy == cors_policy_json
          logger.debug "=> CORS policy is already up to date for #{bucket_name}."
          return
        end
      end

      begin
        logger.info "Setting CORS policy for #{bucket_name}..."

        File.open("cors-policy.json", "w") { |f| f.puts cors_policy_string }

        `AWS_ACCESS_KEY_ID=#{access_key_id} \
        AWS_SECRET_ACCESS_KEY=#{secret_access_key} \
          aws s3api put-bucket-cors \
          --bucket #{bucket_name} \
          --cors-configuration "file://cors-policy.json"`
        unless $?.success?
          raise "Something went wrong while setting the S3 bucket CORS policy!"
        end
        logger.info "=> Successfully set CORS policy for #{bucket_name}."
      ensure
        FileUtils.rm_f "cors-policy.json"
      end
    end

    def add_docker_registry!
      require_config(%i[docker_registry_url docker_registry_username docker_registry_password])

      registry_url = config.fetch(:docker_registry_url)

      logger.debug "Looking up existing Docker registries..."
      registries_response = `convox api get /registries`
      unless $?.success?
        raise "Something went wrong while fetching the list of registries!"
      end
      registries = JSON.parse(registries_response)

      if registries.any? { |r| r["server"] == registry_url }
        logger.debug "=> Docker Registry already exists: #{registry_url}"
        return true
      end

      logger.info "Adding Docker Registry: #{registry_url}..."
      logger.info "=> Documentation: " \
                  "https://docs.convox.com/deployment/private-registries"

      `convox registries add "#{registry_url}" \
        "#{config.fetch(:docker_registry_username)}" \
        "#{config.fetch(:docker_registry_password)}"`
      unless $?.success?
        raise "Something went wrong while adding the #{registry_url} registry!"
      end
    end

    def default_service_domain_name
      require_config(%i[convox_app_name default_service])

      @default_service_domain_name ||= begin
        convox_domain = convox_rack_data["domain"]
        elb_name_and_region = convox_domain[/([^\.]*\.[^\.]*)\..*/, 1]
        unless elb_name_and_region.present?
          raise "Something went wrong while parsing the ELB name and region! " \
                "(#{elb_name_and_region})"
        end
        app = config.fetch(:convox_app_name)
        service = config.fetch(:default_service)

        # Need to return downcase host so that `config.hosts` works with Rails applications
        "#{app}-#{service}.#{elb_name_and_region}.convox.site".downcase
      end
    end

    def run_convox_command!(cmd, env = {})
      command = "convox #{cmd}"
      system env, command
      raise "Error running: #{command}" unless $?.success?
    end

    private

    def load_auth_from_file
      return {} unless File.exist?(AUTH_FILE)

      begin
        JSON.parse(File.read(AUTH_FILE))
      rescue
        {}
      end
    end

    def require_config(required_keys)
      required_keys.each do |k|
        raise "#{k} is missing from the config!" unless config[k]
      end
    end
  end
end

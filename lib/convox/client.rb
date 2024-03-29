# frozen_string_literal: true

require 'logger'
require 'json'
require 'fileutils'
require 'rubygems'
require 'os'
require 'erb'

module Convox
  class Client
    CONVOX_CONFIG_DIR = if OS.mac?
                          # Convox v3 moved this to ~/Library/Preferences/convox/ on Mac
                          File.expand_path('~/Library/Preferences/convox').freeze
                        else
                          File.expand_path('~/.convox').freeze
                        end

    CURRENT_FILE = File.join(CONVOX_CONFIG_DIR, 'current')

    attr_accessor :logger, :config

    def cli_version_string
      return @cli_version_string if @cli_version_string

      cli_version_string ||= `convox --version`
      return unless $CHILD_STATUS.success?

      @cli_version_string = cli_version_string.chomp
    end

    def cli_version
      return unless cli_version_string.is_a?(String)

      if cli_version_string.match?(/^\d+\.\d+\.\d+/)
        @cli_version ||= Gem::Version.new(version_string)
      end
      @cli_version
    end

    def convox_2_cli?
      return false unless cli_version_string.is_a?(String)

      cli_version_string.match?(/^20\d+$/)
    end

    def convox_3_cli?
      return false if !cli_version_string.is_a?(String) ||
                      convox_2_cli? ||
                      !cli_version_string.match?(/^\d+\.\d+\.\d+/)

      cli_version = Gem::Version.new(cli_version_string)
      cli_version >= Gem::Version.new('3.0.0') &&
        cli_version < Gem::Version.new('4.0.0')
    end

    def initialize(options = {})
      @logger = Logger.new($stdout)
      logger.level = options[:log_level] || Logger::INFO
      @config = options[:config] || {}
    end

    # Convox v3 creates a folder for each rack for the Terraform config
    def rack_dir
      stack_name = config.fetch(:stack_name)
      File.join(CONVOX_CONFIG_DIR, 'racks', stack_name)
    end

    def backup_convox_host_and_rack
      FileUtils.mkdir_p CONVOX_CONFIG_DIR

      path = File.join(CONVOX_CONFIG_DIR, 'current')
      return unless File.exist?(path)

      bak_file = "#{path}.bak"
      logger.info "Moving existing #{path} to #{bak_file}..."
      FileUtils.mv(path, bak_file)
    end

    def install_convox
      require_config(%i[aws_region stack_name])
      region = config.fetch(:aws_region)
      stack_name = config.fetch(:stack_name)

      if rack_already_installed?
        logger.info "There is already a Convox rack named #{stack_name}. Using this rack."
        logger.debug 'If you need to start over, you can run: ' \
                     "convox rack uninstall #{stack_name}    " \
                     '(Make sure you export AWS_ACCESS_KEY_ID and ' \
                     "AWS_SECRET_ACCESS_KEY first.)\n" \
                     "If this fails, you can try deleting the rack directory: rm -rf #{rack_dir}"
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
        'AWS_REGION' => region,
        'AWS_ACCESS_KEY_ID' => config.fetch(:aws_access_key_id),
        'AWS_SECRET_ACCESS_KEY' => config.fetch(:aws_secret_access_key)
      }
      # Set proxy_protocol=true by default to forward client IPs
      command = %(rack install aws \
"#{config.fetch(:stack_name)}" \
"node_type=#{config.fetch(:instance_type)}" \
"proxy_protocol=true" \
"region=#{config.fetch(:aws_region)}")
      # us-east constantly has problems with the us-east-1c AZ:
      # "Cannot create cluster 'ds-enterprise-cx3' because us-east-1c, the targeted
      # availability zone, does not currently have sufficient capacity to support the cluster.
      # Retry and choose from these availability zones:
      # us-east-1a, us-east-1b, us-east-1d, us-east-1e, us-east-1f
      if config.fetch(:aws_region) == 'us-east-1'
        command += ' "availability_zones=us-east-1a,us-east-1b,us-east-1d,us-east-1e,us-east-1f"'
      end

      run_convox_command!(command, env, rack_arg: false)
    end

    def rack_already_installed?
      require_config(%i[aws_region stack_name])
      return true if File.exist?(rack_dir)

      false
    end

    # Auth for a detached rack is not saved in the auth file anymore.
    # It can be found in the terraform state:
    # ~/Library/Preferences/convox/racks/ds-enterprise-cx3/terraform.tfstate
    # Under outputs/api/value. The API URL contains the convox username and API token as basic auth.
    def validate_convox_rack_and_write_current!
      require_config(%i[aws_region stack_name])

      unless rack_already_installed?
        raise "Could not find rack terraform directory at: #{rack_dir}"
      end

      # Tells the Convox CLI to use our terraform stack
      stack_name = config.fetch(:stack_name)
      write_current(stack_name)
      stack_name
    end

    def write_current(rack_name)
      logger.debug "Setting convox rack to #{rack_name} (in #{CURRENT_FILE})..."
      current_hash = { name: rack_name, type: 'terraform' }
      File.open(CURRENT_FILE, 'w') { |f| f.puts current_hash.to_json }
    end

    def validate_convox_rack_api!
      require_config(%i[
                       aws_region
                       stack_name
                       instance_type
                     ])
      logger.debug 'Validating that convox rack has the correct attributes...'
      # Convox 3 racks no longer return info about region or type. (These are blank strings.)
      {
        provider: 'aws',
        # region: config.fetch(:aws_region),
        # type: config.fetch(:instance_type),
        name: config.fetch(:stack_name)
      }.each do |k, v|
        convox_value = convox_rack_data[k.to_s]
        if convox_value != v
          raise "Convox data did not match! Expected #{k} to be '#{v}', " \
                "but was: '#{convox_value}'"
        end
      end
      logger.debug '=> Convox rack has the correct attributes.'
      true
    end

    def convox_rack_data
      @convox_rack_data ||= begin
        logger.debug 'Fetching convox rack attributes...'
        command = "convox api get /system --rack #{config.fetch(:stack_name)}"
        logger.debug "+ #{command}"
        # It can take a while for the API to be ready.
        start_time = Time.now
        convox_output = nil
        loop do
          convox_output = `#{command}`
          break if $CHILD_STATUS.success?

          if Time.now - start_time > 360
            raise 'Could not connect to Convox rack API!'
          end

          logger.debug 'Waiting for Convox rack API to be ready... (can take a few minutes)'
          sleep 5
        end

        JSON.parse(convox_output)
      end
    end

    def create_convox_app!
      require_config(%i[convox_app_name])
      return true if convox_app_exists?

      app_name = config.fetch(:convox_app_name)

      logger.info "Creating app: #{app_name}..."
      logger.info '=> Documentation: ' \
                  'https://docs.convox.com/reference/cli/apps/'

      # NOTE: --wait flags were removed in Convox 3. It now waits by default.
      run_convox_command! "apps create #{app_name}"

      retries = 0
      loop do
        break if convox_app_exists?

        if retries > 5
          raise "Something went wrong while creating the #{app_name} app! " \
                '(Please wait a few moments and then restart the installation script.)'
        end
        logger.info "Waiting for #{app_name} to be ready..."
        sleep 3
        retries += 1
      end

      logger.info "=> #{app_name} app created!"
    end

    def set_default_app_for_directory!
      logger.info 'Setting default app in ./.convox/app...'
      FileUtils.mkdir_p File.expand_path('./.convox')
      File.open(File.expand_path('./.convox/app'), 'w') do |f|
        f.puts config.fetch(:convox_app_name)
      end
    end

    def convox_app_exists?
      require_config(%i[convox_app_name])
      app_name = config.fetch(:convox_app_name)

      logger.debug "Looking for existing #{app_name} app..."
      convox_output = `convox api get /apps --rack #{config.fetch(:stack_name)}`
      raise 'convox command failed!' unless $CHILD_STATUS.success?

      apps = JSON.parse(convox_output)
      apps.each do |app|
        if app['name'] == app_name
          logger.debug "=> Found #{app_name} app."
          return true
        end
      end
      logger.debug "=> Did not find #{app_name} app."
      false
    end

    # Create the s3 bucket, and also apply a CORS configuration
    # Convox v3 update - They removed support for S3 resources, so we have to do
    # in terraform now (which is actually pretty nice!)
    def add_s3_bucket
      require_config(%i[s3_bucket_name])

      unless config.key? :s3_bucket_cors_rule
        logger.debug 'No CORS rule provided in config: s3_bucket_cors_rule   (optional)'
        return
      end

      write_terraform_template('s3_bucket')
    end

    def add_rds_database
      require_config(%i[database_username database_password])
      write_terraform_template('rds')
    end

    def add_elasticache_cluster
      write_terraform_template('elasticache')
    end

    def write_terraform_template(name)
      template_path = File.join(__dir__, "../../terraform/#{name}.tf.erb")
      unless File.exist?(template_path)
        raise "Could not find terraform template at: #{template_path}"
      end

      template = ERB.new(File.read(template_path))
      template_output = template.result(binding)

      tf_file_path = File.join(rack_dir, "#{name}.tf")
      logger.debug "Writing terraform config to #{tf_file_path}..."
      File.open(tf_file_path, 'w') { |f| f.puts template_output }
    end

    def apply_terraform_update!
      logger.info 'Applying terraform update...'
      command = if ENV['DEBUG_TERRAFORM']
                  'terraform plan'
                else
                  'terraform apply -auto-approve'
                end
      logger.debug "+ #{command}"

      env = {
        'AWS_ACCESS_KEY_ID' => config.fetch(:aws_access_key_id),
        'AWS_SECRET_ACCESS_KEY' => config.fetch(:aws_secret_access_key)
      }
      Dir.chdir(rack_dir) do
        system env, command
        raise 'terraform command failed!' unless $CHILD_STATUS.success?
      end
    end

    def terraform_state
      tf_state_file = File.join(rack_dir, 'terraform.tfstate')
      JSON.parse(File.read(tf_state_file))
    end

    def terraform_resource(resource_type, resource_name)
      resource = terraform_state['resources'].find do |resource|
        resource['type'] == resource_type && resource['name'] == resource_name
      end
      return resource if resource

      raise "Could not find #{resource_type} resource named #{resource_name} in terraform state!"
    end

    def s3_bucket_details
      require_config(%i[s3_bucket_name])

      s3_bucket = terraform_resource('aws_s3_bucket', 'docs_s3_bucket')
      bucket_attributes = s3_bucket['instances'][0]['attributes']
      access_key = terraform_resource('aws_iam_access_key', 'docspring_user_access_key')
      key_attributes = access_key['instances'][0]['attributes']

      {
        access_key_id: key_attributes['id'],
        secret_access_key: key_attributes['secret'],
        name: bucket_attributes['bucket']
      }
    end

    def rds_details
      require_config(%i[database_username database_password])

      database = terraform_resource('aws_db_instance', 'rds_database')
      database_attributes = database['instances'][0]['attributes']

      username = database_attributes['username']
      password = database_attributes['password']
      endpoint = database_attributes['endpoint']
      postgres_url = "postgres://#{username}:#{password}@#{endpoint}/app"
      {
        postgres_url: postgres_url
      }
    end

    def elasticache_details
      require_config(%i[s3_bucket_name])

      # Just ensure that the bucket exists in the state
      cluster = terraform_resource('aws_elasticache_cluster', 'elasticache_cluster')
      cluster_attributes = cluster['instances'][0]['attributes']
      cache_node = cluster_attributes['cache_nodes'][0]
      redis_url = "redis://#{cache_node['address']}:#{cache_node['port']}/0"

      {
        redis_url: redis_url
      }
    end

    def add_docker_registry!
      require_config(%i[docker_registry_url docker_registry_username docker_registry_password])

      registry_url = config.fetch(:docker_registry_url)

      logger.debug 'Looking up existing Docker registries...'
      registries_response = `convox api get /registries --rack #{config.fetch(:stack_name)}`
      unless $CHILD_STATUS.success?
        raise 'Something went wrong while fetching the list of registries!'
      end

      registries = JSON.parse(registries_response)

      if registries.any? { |r| r['server'] == registry_url }
        logger.debug "=> Docker Registry already exists: #{registry_url}"
        return true
      end

      logger.info "Adding Docker Registry: #{registry_url}..."
      logger.info '=> Documentation: ' \
                  'https://docs.convox.com/configuration/private-registries/'

      `convox registries add "#{registry_url}" \
        "#{config.fetch(:docker_registry_username)}" \
        "#{config.fetch(:docker_registry_password)}" \
        --rack #{config.fetch(:stack_name)}`
      return if $CHILD_STATUS.success?

      raise "Something went wrong while adding the #{registry_url} registry!"
    end

    def default_service_domain_name
      require_config(%i[convox_app_name])

      app_name = config.fetch(:convox_app_name)
      default_service = config[:default_service] || 'web'

      convox_api_url = terraform_state['outputs']['api']['value']
      convox_router_host = convox_api_url.split('@').last.sub(/^api\./, '')

      [default_service, app_name, convox_router_host].join('.').downcase
    end

    def run_convox_command!(cmd, env = {}, rack_arg: true)
      # Always include the rack as an argument, to
      # make sure that 'convox switch' doesn't affect any commands
      command = "convox #{cmd}"
      if rack_arg
        command = "#{command} --rack #{config.fetch(:stack_name)}"
      end
      logger.debug "+ #{command}"
      system env, command
      raise "Error running: #{command}" unless $CHILD_STATUS.success?
    end

    private

    def require_config(required_keys)
      required_keys.each do |k|
        raise "#{k} is missing from the config!" unless config[k]
      end
    end
  end
end

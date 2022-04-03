#!/usr/bin/env ruby
# frozen_string_literal: true

# Use Bundler inline for your real installation script
# require "bundler/inline"

# gemfile do
#   source "https://rubygems.org"
#   gem "convox_installer"
# end

$LOAD_PATH << File.expand_path('../lib', __dir__)
require 'pry-byebug'

require 'convox_installer'
include ConvoxInstaller

@log_level = Logger::DEBUG

MINIMAL_HEALTH_CHECK_PATH = '/health/site'
COMPLETE_HEALTH_CHECK_PATH = '/health'

S3_BUCKET_CORS_RULE = <<-TERRAFORM
  cors_rule {
    allowed_headers = ["Authorization", "cache-control", "x-requested-with"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3000
  }
TERRAFORM

@prompts = ConvoxInstaller::Config::DEFAULT_PROMPTS + [
  {
    section: 'Docker Registry Authentication',
    info: "You should have received authentication details for the Docker Registry\n" \
          'via email. If not, please contact support@example.com'
  },
  {
    key: :docker_registry_url,
    title: 'Docker Registry URL',
    value: '691950705664.dkr.ecr.us-east-1.amazonaws.com'
  },
  {
    key: :docker_registry_username,
    title: 'Docker Registry Username'
  },
  {
    key: :docker_registry_password,
    title: 'Docker Registry Password'
  },
  {
    key: :convox_app_name,
    title: 'Convox App Name',
    value: 'convox-app'
  },
  {
    key: :default_service,
    title: 'Default Convox Service (for domain)',
    value: 'web',
    hidden: true
  },
  {
    key: :admin_email,
    title: 'Admin User Email',
    prompt: 'Please enter the email address you would like to use ' \
            'for the default admin user',
    default: 'admin@example.com'
  },
  {
    key: :admin_password,
    title: 'Admin User Password',
    value: -> { SecureRandom.hex(8) }
  },
  {
    key: :s3_bucket_name,
    title: 'S3 Bucket for Uploads',
    value: -> { "app-uploads-#{SecureRandom.hex(4)}" }
  },
  {
    key: :s3_bucket_cors_rule,
    value: S3_BUCKET_CORS_RULE,
    hidden: true
  },
  {
    key: :database_username,
    value: 'example_app',
    hidden: true
  },
  {
    key: :database_password,
    value: -> { SecureRandom.hex(16) },
    hidden: true
  }
]

ensure_requirements!
config = prompt_for_config

backup_convox_host_and_rack
install_convox

validate_convox_auth_and_write_host!
validate_convox_rack_api!

create_convox_app!
set_default_app_for_directory!
add_docker_registry!
create_s3_bucket!

puts '=> Generating secret keys for authentication sessions and encryption...'
secret_key_base = SecureRandom.hex(64)
data_encryption_key = SecureRandom.hex(32)

puts "======> Default domain: #{default_service_domain_name}"
puts '        You can use this as a CNAME record after configuring a domain in convox.yml'
puts '        (Note: SSL will be configured automatically.)'

puts '=> Setting environment variables to configure the application...'

env = {
  'HEALTH_CHECK_PATH' => MINIMAL_HEALTH_CHECK_PATH,
  'DOMAIN_NAME' => default_service_domain_name,
  'AWS_ACCESS_KEY_ID' => s3_bucket_details.fetch(:access_key_id),
  'AWS_ACCESS_KEY_SECRET' => s3_bucket_details.fetch(:secret_access_key),
  'AWS_UPLOADS_S3_BUCKET' => s3_bucket_details.fetch(:name),
  'AWS_UPLOADS_S3_REGION' => config.fetch(:aws_region),
  'SECRET_KEY_BASE' => secret_key_base,
  'DATA_ENCRYPTION_KEY' => data_encryption_key,
  'ADMIN_NAME' => 'Admin',
  'ADMIN_EMAIL' => config.fetch(:admin_email),
  'ADMIN_PASSWORD' => config.fetch(:admin_password)
}

env_command_params = env.map { |k, v| "#{k}=\"#{v}\"" }.join(' ')
run_convox_command! "env set #{env_command_params}"

puts '=> Initial deploy...'
puts '-----> Documentation: https://docs.convox.com/deployment/deploying-changes/'
run_convox_command! 'deploy --wait'

puts '=> Setting up the database...'
run_convox_command! 'run web rake db:create db:migrate db:seed'

puts '=> Updating the health check path to include database tests...'
run_convox_command! "env set --promote --wait HEALTH_CHECK_PATH=#{COMPLETE_HEALTH_CHECK_PATH}"

puts
puts 'All done!'
puts
puts "You can now visit #{default_service_domain_name} and sign in with:"
puts
puts "    Email:    #{config.fetch(:admin_email)}"
puts "    Password: #{config.fetch(:admin_password)}"
puts
puts 'You can configure a custom domain name, auto-scaling, and other options in convox.yml.'
puts 'To deploy your changes, run: convox deploy --wait'
puts
puts "IMPORTANT: You should be very careful with the 'resources' section in convox.yml."
puts 'If you remove, rename, or change these resources, then Convox will delete'
puts 'your database. This will result in downtime and a loss of data.'
puts 'To prevent this from happening, you can sign into your AWS account,'
puts 'visit the RDS and ElastiCache services, and enable "Termination Protection"'
puts 'for your database resources.'
puts
puts 'To learn more about the convox CLI, run: convox --help'
puts
puts '  * View the Convox documentation:  https://docs.convox.com/'
puts
puts
puts 'To completely uninstall Convox from your AWS account,'
puts 'run the following steps (in this order):'
puts
puts ' 1) Disable "Termination Protection" for any resource where it was enabled.'
puts
puts " 2) Delete all files from the #{config.fetch(:s3_bucket_name)} S3 bucket:"
puts
puts "    export AWS_ACCESS_KEY_ID=#{config.fetch(:aws_access_key_id)}"
puts "    export AWS_SECRET_ACCESS_KEY=#{config.fetch(:aws_secret_access_key)}"
puts "    aws s3 rm s3://#{s3_bucket_details.fetch(:name)} --recursive"
puts
puts " 3) Delete the #{config.fetch(:s3_bucket_name)} S3 bucket:"
puts
puts "    convox rack resources delete #{config.fetch(:s3_bucket_name)} --wait"
puts
puts ' 4) Uninstall Convox (deletes all CloudFormation stacks and AWS resources):'
puts
puts "    convox rack uninstall aws #{config.fetch(:stack_name)}"
puts

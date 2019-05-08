#!/usr/bin/env ruby
# frozen_string_literal: true
require "pry-byebug"
$LOAD_PATH << File.expand_path("../../lib", __FILE__)

require "convox_installer"
include ConvoxInstaller

@log_level = Logger::DEBUG

@prompts = ConvoxInstaller::Config::DEFAULT_PROMPTS + [
  {
    section: "ECR Authentication",
    info: "You should have received authentication details for the Docker Registry\n" \
    "via email. If not, please contact support@example.com",
  },
  {
    key: :ecr_access_key_id,
    title: "Docker Registry Access Key ID",
  },
  {
    key: :ecr_secret_access_key,
    title: "Docker Registry Secret Access Key",
  },
  {
    key: :admin_email,
    title: "Admin User Email",
    prompt: "Please enter the email address you would like to use " \
    "for the default admin user",
    default: "admin@example.com",
  },
  {
    key: :admin_password,
    title: "Admin User Password",
    force_default: -> () { SecureRandom.hex(8) },
  },
]

ensure_requirements
prompt_for_config

# backup_convox_host_and_rack
# install_convox

check_convox_auth

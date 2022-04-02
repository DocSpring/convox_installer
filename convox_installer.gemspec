# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'convox_installer/version'

Gem::Specification.new do |s|
  s.name = 'convox_installer'
  s.version = ConvoxInstaller::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ['Form Applications Inc.']
  s.email = ['support@formapi.io']
  s.homepage = 'https://github.com/FormAPI/convox_installer'
  s.summary = 'Build a Convox installation workflow'
  s.description = 'Build a Convox installation workflow'
  s.license = 'MIT'
  s.required_ruby_version = '>= 2.5'

  s.add_runtime_dependency 'activesupport', '>= 5.2.3'
  s.add_runtime_dependency 'highline', '>= 1.7.10'
  s.add_runtime_dependency 'httparty', '>= 0.17.0'
  s.add_runtime_dependency 'json', '>= 2.2.0'
  s.add_runtime_dependency 'os', '>= 1.0.1'

  s.files = `git ls-files`.split("\n").uniq.sort.reject(&:empty?) - ['Gemfile.lock']
  s.test_files = `git ls-files spec test`.split("\n")
  s.executables = []
  s.require_paths = ['lib']
  s.metadata['rubygems_mfa_required'] = 'true'
end

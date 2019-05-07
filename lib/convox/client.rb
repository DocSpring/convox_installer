# frozen_string_literal: true

require 'json'

module Convox
  class Client
    AUTH_FILE = '~/.convox/auth'

    attr_accessor :auth

    def initialize
      load_auth
    end

    private

    def load_auth
      return unless File.exist?(AUTH_FILE)

      self.auth = JSON.parse(File.read(AUTH_FILE))
    end
  end
end

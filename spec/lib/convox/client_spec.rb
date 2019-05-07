# frozen_string_literal: true

require 'convox/client'

RSpec.describe Convox::Client do
  it 'should find the authentication details in ~/.convox.auth' do
    expect(File).to receive(:exist?).with('~/.convox/auth').and_return(true)
    expect(File).to receive(:read).with('~/.convox/auth').and_return(
      '{ "test.example.com": "1234567890" }'
    )

    client = Convox::Client.new
    expect(client.auth).to eq('test.example.com' => '1234567890')
  end
end

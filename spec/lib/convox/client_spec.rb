# frozen_string_literal: true

require "convox/client"

RSpec.describe Convox::Client do
  it "finds the authentication details in ~/.convox/auth" do
    expect(File).to receive(:exist?).with("~/.convox/auth").and_return(true)
    expect(File).to receive(:read).with("~/.convox/auth").and_return(
      '{ "test.example.com": "1234567890" }'
    )

    client = described_class.new
    expect(client.auth).to eq("test.example.com" => "1234567890")
  end

  it "should backup existing Convox host and rack files" do
    expect(File).to receive(:exist?).with("~/.convox/host").and_return(true)
    expect(File).to receive(:exist?).with("~/.convox/rack").and_return(true)
    expect(FileUtils).to receive(:mv).with("~/.convox/host", "~/.convox/host.bak")
    expect(FileUtils).to receive(:mv).with("~/.convox/rack", "~/.convox/rack.bak")

    client = described_class.new
    client.backup_convox_config
  end
end

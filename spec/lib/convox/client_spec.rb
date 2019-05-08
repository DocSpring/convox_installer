# frozen_string_literal: true

require "convox/client"

RSpec.describe Convox::Client do
  let(:home_dir) { File.expand_path("~") }

  it "finds the authentication details in ~/.convox/auth" do
    expect(File).to receive(:exist?).with("#{home_dir}/.convox/auth").and_return(true)
    expect(File).to receive(:read).with("#{home_dir}/.convox/auth").and_return(
      '{ "test.example.com": "1234567890" }'
    )
    client = described_class.new
    expect(client.auth).to eq("test.example.com" => "1234567890")
  end

  it "should backup existing Convox host and rack files" do
    expect(File).to receive(:exist?).with(
      "#{home_dir}/.convox/host"
    ).and_return(true)
    expect(File).to receive(:exist?).with(
      "#{home_dir}/.convox/rack"
    ).and_return(true)
    expect(FileUtils).to receive(:mv).with(
      "#{home_dir}/.convox/host", "#{home_dir}/.convox/host.bak"
    )
    expect(FileUtils).to receive(:mv).with(
      "#{home_dir}/.convox/rack", "#{home_dir}/.convox/rack.bak"
    )

    client = described_class.new
    expect(client.logger).to receive(:info).twice

    client.backup_convox_config!
  end
end

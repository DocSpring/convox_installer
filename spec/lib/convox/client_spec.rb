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

    client.backup_convox_host_and_rack
  end

  describe "#install" do
    it "should require the correct config vars" do
      client = described_class.new
      expect { client.install_convox }.to raise_error("aws_region is missing from the config!")

      client = described_class.new(config: {aws_region: "asdf"})
      expect { client.install_convox }.to raise_error("aws_access_key_id is missing from the config!")
    end

    it "should run the correct convox CLI command" do
      client = described_class.new(
        config: {
          aws_region: "us-east-1",
          aws_access_key_id: "asdf",
          aws_secret_access_key: "1234",
          stack_name: "asdf",
          instance_type: "t3.medium",
        },
      )

      expect(client.logger).to receive(:info)
      expect(client).to receive(:run_command).with(
        "convox rack install aws --name \"asdf\" \"InstanceType=t3.medium\" " \
        "\"BuildInstance=\"",
        "AWS_ACCESS_KEY_ID" => "asdf",
        "AWS_REGION" => "us-east-1",
        "AWS_SECRET_ACCESS_KEY" => "1234",
      )
      client.install_convox
    end
  end

  describe "#validate_convox_auth_and_set_host!" do
    it "should require the correct config vars" do
      client = described_class.new
      expect { client.validate_convox_auth_and_set_host! }.to raise_error("aws_region is missing from the config!")
    end

    it "should raise an error if auth file is missing" do
      client = described_class.new(
        config: {
          aws_region: "us-east-1",
          stack_name: "asdf",
        },
      )
      expect(File).to receive(:exist?).with(
        "#{home_dir}/.convox/auth"
      ).and_return(false)

      expect {
        client.validate_convox_auth_and_set_host!
      }.to raise_error(/Could not find auth file at /)
    end

    it "should set ~/.convox/host if a matching host is found in the auth file" do
      expect(File).to receive(:exist?).with(
        "#{home_dir}/.convox/auth"
      ).twice.and_return(true)

      expect(File).to receive(:read).with("#{home_dir}/.convox/auth").and_return(
        '{ "convox-test-697645520.us-west-2.elb.amazonaws.com": "1234567890" }'
      )
      client = described_class.new(
        config: {
          aws_region: "us-west-2",
          stack_name: "convox-test",
        },
      )
      expect(client).to receive(:set_host).with(
        "convox-test-697645520.us-west-2.elb.amazonaws.com"
      )
      expect(client.validate_convox_auth_and_set_host!).to(
        eq("convox-test-697645520.us-west-2.elb.amazonaws.com")
      )
    end

    it "should raise an error if no matching host is found" do
      expect(File).to receive(:exist?).with(
        "#{home_dir}/.convox/auth"
      ).twice.and_return(true)

      expect(File).to receive(:read).with("#{home_dir}/.convox/auth").and_return(
        '{ "convox-test-697645520.us-west-2.elb.amazonaws.com": "1234567890" }'
      )
      client = described_class.new(
        config: {
          aws_region: "us-east-1",
          stack_name: "convox-test",
        },
      )
      expect {
        client.validate_convox_auth_and_set_host!
      }.to raise_error("Could not find matching authentication for " \
           "region: us-east-1, stack: convox-test")
    end

    it "should raise an error if it finds multiple matching hosts" do
      expect(File).to receive(:exist?).with(
        "#{home_dir}/.convox/auth"
      ).twice.and_return(true)

      expect(File).to receive(:read).with("#{home_dir}/.convox/auth").and_return(
        '{ "convox-test-697645520.us-west-2.elb.amazonaws.com": "1234567890", ' \
        '"convox-test-1234123412.us-west-2.elb.amazonaws.com": "1234567890" }'
      )
      client = described_class.new(
        config: {
          aws_region: "us-west-2",
          stack_name: "convox-test",
        },
      )
      expect {
        client.validate_convox_auth_and_set_host!
      }.to raise_error("Found multiple matching hosts for " \
           "region: us-west-2, stack: convox-test")
    end
  end
end

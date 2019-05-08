# frozen_string_literal: true

require "convox_installer"
require "securerandom"

RSpec.describe ConvoxInstaller::Config do
  after(:each) do
    ENV.delete "AWS_REGION"
    ENV.delete "AWS_ACCESS_KEY_ID"
  end

  it "loads the saved config from ~/.convox/installer_config" do
    expect(described_class).to receive(:config_file_exists?).and_return(true)
    expect(described_class).to receive(:read_config_file).and_return(
      '{ "config": { "aws_region": "us-west-2", "aws_access_key_id": "1234" } }'
    )
    config = described_class.new

    expect(config.config).to eq(
      aws_region: "us-west-2",
      aws_access_key_id: "1234",
    )
  end

  it "loads config from ENV vars" do
    expect(described_class).to receive(:config_file_exists?).and_return(false)
    ENV["AWS_REGION"] = "us-east-1"
    ENV["AWS_ACCESS_KEY_ID"] = "2345"

    config = described_class.new
    expect(config.config).to eq(
      aws_region: "us-east-1",
      aws_access_key_id: "2345",
    )
  end

  it "prompts the user for their AWS details, and re-prompts to correct mistakes" do
    expect(described_class).to receive(:config_file_exists?).and_return(false)
    input = StringIO.new
    output = StringIO.new
    highline = HighLine.new(input, output)

    input << "\nus-north-12\nasdf\nxkcd\n\nn\nformapi-test\n\nsdfg\n\n\ny\n"
    input.rewind

    config = described_class.new(highline: highline)
    expect(config).to receive(:save_config_to_file).exactly(10).times

    expect(config.config).to eq({})
    config.prompt_for_config
    expect(config.config).to eq(
      :stack_name => "formapi-test",
      :aws_access_key_id => "sdfg",
      :aws_region => "us-north-12",
      :aws_secret_access_key => "xkcd",
      :instance_type => "t3.medium",
    )
    output.rewind
    stripped_output = output.read.lines.map(&:rstrip).join("\n")
    expected_output = <<-EOS
Please enter a name for your Convox installation  |formapi-enterprise|
Please enter your AWS Region: |us-east-1|
Admin AWS Credentials
============================================

Please enter your AWS Access Key ID: Please enter your AWS Secret Access Key: Please enter your EC2 Instance Type: |t3.medium|
============================================
                 SUMMARY
============================================

    Convox Stack Name:       formapi-enterprise
    AWS Region:              us-north-12
    AWS Access Key ID:       asdf
    AWS Secret Access Key:   xkcd
    EC2 Instance Type:       t3.medium

We've saved your configuration to: /Users/ndbroadbent/.convox/installer_config
If anything goes wrong during the installation, you can restart the script to reload the config and continue.

Please double check all of these configuration details.
Would you like to start the Convox installation? (press 'n' to correct any settings)

Please enter a name for your Convox installation  |formapi-enterprise|
Please enter your AWS Region: |us-north-12|
Admin AWS Credentials
============================================

Please enter your AWS Access Key ID: |asdf| Please enter your AWS Secret Access Key: |xkcd| Please enter your EC2 Instance Type: |t3.medium|
============================================
                 SUMMARY
============================================

    Convox Stack Name:       formapi-test
    AWS Region:              us-north-12
    AWS Access Key ID:       sdfg
    AWS Secret Access Key:   xkcd
    EC2 Instance Type:       t3.medium

We've saved your configuration to: /Users/ndbroadbent/.convox/installer_config
If anything goes wrong during the installation, you can restart the script to reload the config and continue.

Please double check all of these configuration details.
Would you like to start the Convox installation? (press 'n' to correct any settings)
EOS

    # puts stripped_output
    # puts "---------------"
    # puts expected_output
    expect(stripped_output).to eq expected_output.strip
  end

  it "prompts for custom configuration" do
    expect(described_class).to receive(:config_file_exists?).and_return(false)
    input = StringIO.new
    output = StringIO.new
    highline = HighLine.new(input, output)

    custom_prompts = ConvoxInstaller::Config::DEFAULT_PROMPTS + [
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
        title: "Admin Email",
        prompt: "Please enter the email address you would like to use " \
        "for the default admin user",
        default: "admin@example.com",
      },
      {
        key: :admin_password,
        title: "Admin Password",
        force_default: -> () { SecureRandom.hex(8) },
      },
    ]

    input << "\n\nasdf\nxkcd\n\nsdfg\nqwer\n\ny\n"
    input.rewind

    config = described_class.new(highline: highline, prompts: custom_prompts)
    expect(config).to receive(:save_config_to_file).exactly(8).times
    expect(SecureRandom).to receive(:hex).with(8).and_return("99a6f67de0c7a117")

    expect(config.config).to eq({})

    config.prompt_for_config

    expect(config.config).to eq(
      :stack_name => "formapi-enterprise",
      :aws_region => "us-east-1",
      :aws_access_key_id => "asdf",
      :aws_secret_access_key => "xkcd",
      :instance_type => "t3.medium",
      :ecr_access_key_id => "sdfg",
      :ecr_secret_access_key => "qwer",
      :admin_email => "admin@example.com",
      :admin_password => "99a6f67de0c7a117",
    )
    output.rewind
    stripped_output = output.read.lines.map(&:rstrip).join("\n")
    expected_output = <<-EOS
Please enter a name for your Convox installation  |formapi-enterprise|
Please enter your AWS Region: |us-east-1|
Admin AWS Credentials
============================================

Please enter your AWS Access Key ID: Please enter your AWS Secret Access Key: Please enter your EC2 Instance Type: |t3.medium|
ECR Authentication
============================================

Please enter your Docker Registry Access Key ID: Please enter your Docker Registry Secret Access Key: Please enter the email address you would like to use for the default admin user  |admin@example.com|

============================================
                 SUMMARY
============================================

    Convox Stack Name:                   formapi-enterprise
    AWS Region:                          us-east-1
    AWS Access Key ID:                   asdf
    AWS Secret Access Key:               xkcd
    EC2 Instance Type:                   t3.medium
    Docker Registry Access Key ID:       sdfg
    Docker Registry Secret Access Key:   qwer
    Admin Email:                         admin@example.com
    Admin Password:                      99a6f67de0c7a117

We've saved your configuration to: /Users/ndbroadbent/.convox/installer_config
If anything goes wrong during the installation, you can restart the script to reload the config and continue.

Please double check all of these configuration details.
Would you like to start the Convox installation? (press 'n' to correct any settings)
EOS

    # puts stripped_output
    # puts "---------------"
    # puts expected_output
    expect(stripped_output).to eq expected_output.strip
  end
end

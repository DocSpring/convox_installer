# frozen_string_literal: true

require "convox_installer"
require "securerandom"

RSpec.describe ConvoxInstaller::Config do
  before(:each) do
    stub_const('ConvoxInstaller::Config::CONFIG_FILE', '/path/to/.installer_config')
  end

  after(:each) do
    ENV.delete "AWS_REGION"
    ENV.delete "AWS_ACCESS_KEY_ID"
  end

  it "loads the saved config from ./.installer_config" do
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

    input_details = [
      [:stack_name, ""],
      [:aws_region, ""],
      [:instance_type, "c5.xlarge"],
      [:aws_access_key_id, "asdf"],
      [:aws_secret_access_key, "xkcd"],
      [:confirm?, "n"],
      [:stack_name, "convox-test"],
      [:aws_region, "us-north-12"],
      [:instance_type, "t3.medium"],
      [:aws_access_key_id, "sdfg"],
      [:aws_secret_access_key, ""],
      [:confirm?, "y"],
    ]
    input << input_details.map(&:last).join("\n") << "\n"
    input.rewind

    config = described_class.new(highline: highline)
    expect(config).to receive(:save_config_to_file).exactly(10).times

    expect(config.config).to eq({})
    config.prompt_for_config
    expect(config.config).to eq(
      :stack_name => "convox-test",
      :aws_region => "us-north-12",
      :aws_access_key_id => "sdfg",
      :aws_secret_access_key => "xkcd",
      :instance_type => "t3.medium",
    )
    output.rewind
    stripped_output = output.read.lines.map(&:rstrip).join("\n")
    expected_output = <<-EOS
Please enter a name for your Convox installation  |convox|
Please enter your AWS Region: |us-east-1| Please enter your EC2 Instance Type: |t3.medium|
Admin AWS Credentials
============================================

Please enter your AWS Access Key ID: Please enter your AWS Secret Access Key:
============================================
                 SUMMARY
============================================

    Convox Stack Name:       convox
    AWS Region:              us-east-1
    EC2 Instance Type:       c5.xlarge
    AWS Access Key ID:       asdf
    AWS Secret Access Key:   xkcd

We've saved your configuration to: /path/to/.installer_config
If anything goes wrong during the installation, you can restart the script to reload the config and continue.

Please double check all of these configuration details.
Would you like to start the Convox installation? (press 'n' to correct any settings)

Please enter a name for your Convox installation  |convox|
Please enter your AWS Region: |us-east-1| Please enter your EC2 Instance Type: |c5.xlarge|
Admin AWS Credentials
============================================

Please enter your AWS Access Key ID: |asdf| Please enter your AWS Secret Access Key: |xkcd|
============================================
                 SUMMARY
============================================

    Convox Stack Name:       convox-test
    AWS Region:              us-north-12
    EC2 Instance Type:       t3.medium
    AWS Access Key ID:       sdfg
    AWS Secret Access Key:   xkcd

We've saved your configuration to: /path/to/.installer_config
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
        key: :docker_registry_username,
        title: "Docker Registry Access Key ID",
      },
      {
        key: :docker_registry_password,
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
        value: -> () { SecureRandom.hex(8) },
      },
    ]

    input_details = [
      [:stack_name, ""],
      [:aws_region, ""],
      [:instance_type, "c5.xlarge"],
      [:aws_access_key_id, "asdf"],
      [:aws_secret_access_key, "xkcd"],
      [:docker_registry_username, "bob"],
      [:docker_registry_password, "password1"],
      [:admin_email, "admin@test.com"],
      [:confirm?, "y"],
    ]
    input << input_details.map(&:last).join("\n") << "\n"
    input.rewind

    config = described_class.new(highline: highline, prompts: custom_prompts)
    expect(config).to receive(:save_config_to_file).exactly(9).times
    expect(SecureRandom).to receive(:hex).with(8).and_return("99a6f67de0c7a117")

    expect(config.config).to eq({})

    config.prompt_for_config

    expect(config.config).to eq(
      :stack_name => "convox",
      :aws_region => "us-east-1",
      :aws_access_key_id => "asdf",
      :aws_secret_access_key => "xkcd",
      :instance_type => "c5.xlarge",
      :docker_registry_username => "bob",
      :docker_registry_password => "password1",
      :admin_email => "admin@test.com",
      :admin_password => "99a6f67de0c7a117",
    )
    output.rewind
    stripped_output = output.read.lines.map(&:rstrip).join("\n")
    expected_output = <<-EOS
Please enter a name for your Convox installation  |convox|
Please enter your AWS Region: |us-east-1| Please enter your EC2 Instance Type: |t3.medium|
Admin AWS Credentials
============================================

Please enter your AWS Access Key ID: Please enter your AWS Secret Access Key:
ECR Authentication
============================================

Please enter your Docker Registry Access Key ID: Please enter your Docker Registry Secret Access Key: Please enter the email address you would like to use for the default admin user  |admin@example.com|

============================================
                 SUMMARY
============================================

    Convox Stack Name:                   convox
    AWS Region:                          us-east-1
    EC2 Instance Type:                   c5.xlarge
    AWS Access Key ID:                   asdf
    AWS Secret Access Key:               xkcd
    Docker Registry Access Key ID:       bob
    Docker Registry Secret Access Key:   password1
    Admin Email:                         admin@test.com
    Admin Password:                      99a6f67de0c7a117

We've saved your configuration to: /path/to/.installer_config
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

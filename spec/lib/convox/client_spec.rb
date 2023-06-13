# frozen_string_literal: true

require 'convox/client'

RSpec.describe Convox::Client do
  let(:home_dir) { File.expand_path('~') }

  describe 'Convox CLI version' do
    let(:client) { described_class.new }

    it 'returns the convox CLI version output for 20210208170413' do
      expect(client).to receive(:cli_version_string).at_least(:once).and_return('20210208170413')
      expect(client.convox_2_cli?).to be true
      expect(client.convox_3_cli?).to be false
    end

    it 'returns the convox CLI version output for 20200101130413' do
      expect(client).to receive(:cli_version_string).at_least(:once).and_return('20200101130413')
      expect(client.convox_2_cli?).to be true
      expect(client.convox_3_cli?).to be false
    end

    it 'returns the convox CLI version output for 3.0.0' do
      expect(client).to receive(:cli_version_string).at_least(:once).and_return('3.0.0')
      expect(client.convox_2_cli?).to be false
      expect(client.convox_3_cli?).to be true
    end

    it 'returns the convox CLI version output for 3.1.3' do
      expect(client).to receive(:cli_version_string).at_least(:once).and_return('3.1.3')
      expect(client.convox_2_cli?).to be false
      expect(client.convox_3_cli?).to be true
    end

    it 'returns the convox CLI version output for 4.0.0' do
      expect(client).to receive(:cli_version_string).at_least(:once).and_return('4.0.0')
      expect(client.convox_2_cli?).to be false
      expect(client.convox_3_cli?).to be false
    end
  end

  it 'backups existing Convox host and rack files' do
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

  describe '#install' do
    it 'requires the correct config vars' do
      client = described_class.new
      expect { client.install_convox }.to raise_error('aws_region is missing from the config!')

      client = described_class.new(config: { aws_region: 'us-east-1' })
      expect { client.install_convox }.to raise_error('stack_name is missing from the config!')
    end

    it 'runs the correct convox CLI command' do
      client = described_class.new(
        config: {
          aws_region: 'us-east-1',
          aws_access_key_id: 'asdf',
          aws_secret_access_key: '1234',
          stack_name: 'asdf',
          instance_type: 't3.medium'
        }
      )

      expect(client.logger).to receive(:info)
      expect(client).to receive(:run_convox_command!).with(
        'rack install aws --name "asdf" "InstanceType=t3.medium" ' \
        '"BuildInstance="',
        'AWS_ACCESS_KEY_ID' => 'asdf',
        'AWS_REGION' => 'us-east-1',
        'AWS_SECRET_ACCESS_KEY' => '1234'
      )
      client.install_convox
    end
  end

  describe '#validate_convox_rack_and_write_current!' do
    it 'requires the correct config vars' do
      client = described_class.new
      expect do
        client.validate_convox_rack_and_write_current!
      end.to raise_error('aws_region is missing from the config!')
    end
  end
end

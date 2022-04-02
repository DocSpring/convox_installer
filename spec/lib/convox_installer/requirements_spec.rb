# frozen_string_literal: true

require 'convox_installer'

RSpec.describe ConvoxInstaller::Requirements do
  let(:convox_cli_version) { '3.3.4' }

  before do
    allow_any_instance_of(
      Convox::Client
    ).to receive(:cli_version_string).and_return(convox_cli_version)
  end

  context 'with no missing packages and correct CLI version' do
    it 'does nothing' do
      req = described_class.new
      expect(req).to receive(:find_command).with('convox').and_return(true)
      expect(req).to receive(:find_command).with('aws').and_return(true)
      expect(req).not_to receive(:quit!)

      expect(req.logger).not_to receive(:error)

      req.ensure_requirements!
    end
  end

  context 'with Mac' do
    context 'with two missing packages' do
      it 'shows the correct error message and quit' do
        expect(OS).to receive(:mac?).and_return(true)

        req = described_class.new
        expect(req).to receive(:find_command).with('convox').and_return(false)
        expect(req).to receive(:find_command).with('aws').and_return(false)
        expect(req).to receive(:quit!)

        expect(req.logger).to receive(:error).with(
          'This script requires the convox and AWS CLI tools.'
        )
        expect(req.logger).to receive(:error).with(
          'Please run: brew install convox awscli'
        )

        req.ensure_requirements!
      end
    end

    context 'with Convox CLI version 20210208170413' do
      let(:convox_cli_version) { '20210208170413' }

      it 'shows the correct error message and quit' do
        req = described_class.new
        expect(req).to receive(:find_command).with('convox').and_return(true)
        expect(req).to receive(:find_command).with('aws').and_return(true)
        expect(req).to receive(:quit!)

        expect(req.logger).to receive(:error).with(
          'This script requires Convox CLI version 3.x.x. Your Convox CLI version is: 20210208170413'
        )
        expect(req.logger).to receive(:error).with(
          "Please run 'brew update convox' or follow the instructions at https://docs.convox.com/getting-started/introduction"
        )

        req.ensure_requirements!
      end
    end

    context 'with one missing packages' do
      it 'shows the correct error message and quit' do
        expect(OS).to receive(:mac?).and_return(true)

        req = described_class.new
        expect(req).to receive(:find_command).with('convox').and_return(false)
        expect(req).to receive(:find_command).with('aws').and_return(true)
        expect(req).to receive(:quit!)

        expect(req.logger).to receive(:error).with(
          'This script requires the convox and AWS CLI tools.'
        )
        expect(req.logger).to receive(:error).with(
          'Please run: brew install convox'
        )

        req.ensure_requirements!
      end
    end
  end

  context 'with Linux' do
    context 'with two missing packages' do
      it 'shows the correct error message and quit' do
        expect(OS).to receive(:mac?).and_return(false)

        req = described_class.new
        expect(req).to receive(:find_command).with('convox').and_return(false)
        expect(req).to receive(:find_command).with('aws').and_return(false)
        expect(req).to receive(:quit!)

        expect(req.logger).to receive(:error).with(
          'This script requires the convox and AWS CLI tools.'
        )
        expect(req.logger).to receive(:error).with('Installation Instructions:')
        expect(req.logger).to receive(:error).with(
          '* convox: https://docs.convox.com/introduction/installation'
        )
        expect(req.logger).to receive(:error).with(
          '* aws: https://docs.aws.amazon.com/cli/latest/' \
          'userguide/cli-chap-install.html'
        )

        req.ensure_requirements!
      end
    end
  end
end

# frozen_string_literal: true

require "convox_installer"

RSpec.describe ConvoxInstaller::Requirements do
  context "with no missing packages" do
    it "should do nothing" do
      req = ConvoxInstaller::Requirements.new
      expect(req).to receive(:find_command).with("convox").and_return(true)
      expect(req).to receive(:find_command).with("aws").and_return(true)
      expect(req).to_not receive(:quit!)

      expect(req.logger).to_not receive(:error)

      req.ensure_requirements
    end
  end

  context "on Mac" do
    context "with two missing packages" do
      it "should show the correct error message and quit" do
        expect(OS).to receive(:mac?).and_return(true)

        req = ConvoxInstaller::Requirements.new
        expect(req).to receive(:find_command).with("convox").and_return(false)
        expect(req).to receive(:find_command).with("aws").and_return(false)
        expect(req).to receive(:quit!)

        expect(req.logger).to receive(:error).with(
          "This script requires the convox and AWS CLI tools."
        )
        expect(req.logger).to receive(:error).with(
          "Please run: brew install convox awscli"
        )

        req.ensure_requirements
      end
    end

    context "with one missing packages" do
      it "should show the correct error message and quit" do
        expect(OS).to receive(:mac?).and_return(true)

        req = ConvoxInstaller::Requirements.new
        expect(req).to receive(:find_command).with("convox").and_return(false)
        expect(req).to receive(:find_command).with("aws").and_return(true)
        expect(req).to receive(:quit!)

        expect(req.logger).to receive(:error).with(
          "This script requires the convox and AWS CLI tools."
        )
        expect(req.logger).to receive(:error).with(
          "Please run: brew install convox"
        )

        req.ensure_requirements
      end
    end
  end

  context "on Linux" do
    context "with two missing packages" do
      it "should show the correct error message and quit" do
        expect(OS).to receive(:mac?).and_return(false)

        req = ConvoxInstaller::Requirements.new
        expect(req).to receive(:find_command).with("convox").and_return(false)
        expect(req).to receive(:find_command).with("aws").and_return(false)
        expect(req).to receive(:quit!)

        expect(req.logger).to receive(:error).with(
          "This script requires the convox and AWS CLI tools."
        )
        expect(req.logger).to receive(:error).with("Installation Instructions:")
        expect(req.logger).to receive(:error).with(
          "* convox: https://docs.convox.com/introduction/installation"
        )
        expect(req.logger).to receive(:error).with(
          "* aws: https://docs.aws.amazon.com/cli/latest/" \
          "userguide/cli-chap-install.html"
        )

        req.ensure_requirements
      end
    end
  end
end

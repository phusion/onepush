require 'optparse'
require 'json'
require_relative '../base'

module Pomodori
  module Commands
    class DeployCommand < Base
      def run
        parse_options
        validate_options
        build_environment_config
        Dir.chdir("#{ROOT}/commands/deploy/ruby")
        exec("bundle", "exec", "cap", "production", "deploy")
      end

    private
      def self.create_default_options
        {
          :setup_addresses => [],
          :deploy_addresses => [],
          :ssh_keys        => [],
          :app_root        => Dir.pwd
        }
      end

      def self.create_option_parser(options)
        OptionParser.new do |opts|
          opts.banner = "Usage: pomodori setup [options]"
          opts.separator ""

          opts.separator "Options:"
          opts.on("--manifest FILENAME", String) do |filename|
            options[:manifest] = JSON.parse(File.read(filename))
          end
          opts.on("--manifest-json JSON", String) do |json|
            options[:manifest] = JSON.parse(json)
          end
          opts.on("--setup-address ADDRESS", String) do |address|
            options[:setup_addresses] << address
          end
          opts.on("--deploy-address ADDRESS", String) do |address|
            options[:deploy_addresses] << address
          end
          opts.on("--ssh-log FILENAME", String) do |filename|
            options[:sshkit_output] = filename
          end
          opts.on("--ssh-key FILENAME", String, "Private key to use for SSH connection") do |filename|
            options[:ssh_keys] << filename
          end
          opts.on("--vagrant-key", "Use Vagrant insecure private key for SSH connection") do
            options[:vagrant_key] = true
          end
          opts.on("--progress") do
            options[:report_progress] = true
          end
          opts.on("--progress-base NUMBER", Float) do |val|
            options[:progress_base] = val
          end
          opts.on("--progress-ceil NUMBER", Float) do |val|
            options[:progress_ceil] = val
          end
          opts.on("--help") do
            options[:help] = true
          end
        end
      end

      def validate_options
        if @options[:manifest].nil?
          abort "Please specify a manifest."
        end
        if @options[:setup_addresses].empty?
          abort "Please specify at least one --setup-address."
        end
        if @options[:deploy_addresses].empty?
          abort "Please specify at least one --deploy-address."
        end
      end
    end
  end
end

require 'optparse'
require 'json'
require 'paint'
require_relative './utils'
require_relative '../base'
require_relative '../setup/params'
require_relative '../../lib/constants'
require_relative '../../lib/utils/hash_with_indifferent_access'

module Pomodori
  module Commands
    class OpenCommand < Base
      def run
        parse_options
        maybe_load_default_config_files
        validate_and_finalize_options
        setup_paint_mode

        utils = OpenUtils.new(@params)
        utils.check_hosts_file_garbage!
        if !utils.hosts_file_up_to_date?
          utils.install_hosts_file_entry
        end
        utils.open_address "http://#{utils.internal_app_hostname}/"
        if utils.using_amazon_ec2?
          puts
          puts "NOTICE: You are on Amazon EC2. Please don't forget to configure your EC2 Security"
          puts "Groups and " + Paint["ensuring that port 80 (HTTP) is accessible.", :bold]
        end
      end

    private
      def self.create_default_options
        HashWithIndifferentAccess.new
      end

      def self.create_option_parser(options)
        OptionParser.new do |opts|
          nl = "\n" + (" " * 37)
          opts.banner = "Usage: pomodori push [options]"
          opts.separator "Pushes the app code at the current Git revision, to the Git repository on the"
          opts.separator "server."
          opts.separator ""
          opts.separator "This command does *not* deploy a new release of your app: it merely ensures"
          opts.separator "that the server has a copy of your app code. Use `pomodori deploy` to deploy a"
          opts.separator "new release. The `deploy` command uses the `push` command internally."
          opts.separator ""

          opts.separator "Options:"
          opts.on("--config FILENAME", String,
            "Load config from given file") do |filename|
            options[:loaded] = true
            options.merge!(JSON.parse(File.read(filename)))
          end
          opts.on("--config-json JSON", String,
            "Load config as a JSON string") do |json|
            options[:loaded] = true
            options.merge!(JSON.parse(json))
          end

          opts.separator ""
          opts.on("--app-root PATH", String,
            "Path to the application. Default: current#{nl}" +
            "working directory") do |value|
            options[:app_root] = value
          end

          opts.separator ""
          opts.on("--help", "Show this help") do
            options[:help] = true
          end
        end
      end

      def validate_and_finalize_options
        if @options[:app_root]
          @options[:app_root] = File.absolute_path(@options[:app_root])
        else
          @options[:app_root] = Dir.pwd
        end

        begin
          @app_config = AppConfig.new(@options.delete(:app_config) || @options)
        rescue ArgumentError => e
          abort(" *** ERROR: " + AppConfig.fixup_error_message(e.message))
        end

        begin
          @params = SetupParams.new(@options)
          @params.app_config = @app_config
        rescue ArgumentError => e
          abort(" *** ERROR: " + fixup_params_error_message(e.message))
        end

        @params.validate_and_finalize!
        @app_config.set_defaults!(@params)
      end
    end
  end
end

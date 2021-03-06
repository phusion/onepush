require 'optparse'
require 'json'
require 'thread'
require 'time'
require 'etc'
require 'fileutils'
require 'paint'
require 'net/http'
require_relative '../base'
require_relative './params'
require_relative '../../lib/utils/hash_with_indifferent_access'

module Pomodori
  module Commands
    class SetupCommand < Base
      def run
        parse_options
        maybe_load_default_config_files
        validate_and_finalize_options
        setup_paint_mode
        prepare_announcement if @options[:announcements]
        if run_capistrano
          report_success
          print_announcement if @options[:announcements]
        else
          report_failure
        end
      end

    private
      def self.create_default_options
        HashWithIndifferentAccess.new(
          :app_server_addresses => [],
          :ssh_keys             => [],
          :announcements        => true
        )
      end

      def self.create_option_parser(options)
        OptionParser.new do |opts|
          nl = "\n" + (" " * 37)
          opts.banner = "Usage: pomodori setup [OPTIONS]"
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
          opts.on("--app-id NAME", String, "The application ID") do |value|
            options[:app_id] = value
          end
          opts.on("--server-address ADDRESS", String,
            "The address of the server to setup. This#{nl}" +
            "parameter sets a single server and#{nl}" +
            "designates it as both an app server and#{nl}" +
            "a database server") do |value|
            options[:server_address] = value
          end
          opts.on("--app-server-address ADDRESS", String,
            "The address of an app server to setup. This#{nl}" +
            "can be specified multiple times for setting#{nl}" +
            "up multiple servers") do |address|
            options[:app_server_addresses] << address
          end
          opts.on("--db-server-address ADDRESS", String,
            "The address of the database server to setup") do |address|
            options[:db_server_address] = address
          end
          opts.on("--if-needed", "Use heuristics to determine whether the#{nl}" +
            "server needs a full re-setup, and exit#{nl}" +
            "early if it doesn't") do
            options[:if_needed] = true
          end
          opts.on("--skip-server-empty-check", "Do not check whether servers are empty") do
            options[:check_server_empty] = false
          end
          opts.on("--ssh-log FILENAME", String, "Log SSH output to the given file") do |filename|
            options[:ssh_log] = filename
          end
          opts.on("--ssh-key FILENAME", String, "Private key to use for SSH connection") do |filename|
            options[:ssh_keys] << filename
          end
          opts.on("--vagrant-key", "Use Vagrant insecure private key for SSH#{nl}" +
            "connections") do
            options[:vagrant_key] = true
          end

          opts.separator ""
          opts.on("--progress", "Output progress indicators") do
            options[:progress] = true
          end
          opts.on("--progress-base NUMBER", Float, "Default: 0") do |val|
            options[:progress_base] = val
          end
          opts.on("--progress-ceil NUMBER", Float, "Default: 1") do |val|
            options[:progress_ceil] = val
          end
          opts.on("--no-announcements", "Skip announcement messages") do
            options[:announcements] = false
          end

          opts.separator ""
          opts.on("--trace", "-t", "Show detailed backtraces and trace tasks") do
            options[:trace] = true
          end
          opts.on("--help", "Show this help") do
            options[:help] = true
          end
        end
      end

      def validate_and_finalize_options
        begin
          app_config = AppConfig.new(@options.delete(:app_config) || @options)
        rescue ArgumentError => e
          abort(" *** ERROR: " + AppConfig.fixup_error_message(e.message))
        end

        begin
          params = SetupParams.new(@options)
          params.app_config = app_config
        rescue ArgumentError => e
          abort(" *** ERROR: " + fixup_params_error_message(e.message))
        end

        params.validate_and_finalize!
        app_config.set_defaults!(params)

        ENV["POMODORI_PARAMS"] = JSON.generate(params)
      end

      def fixup_params_error_message(message)
        # Example message:
        # The property 'domain_names' is required for Pomodori::AppConfig.
        message = message.sub(/ for (.+?)$/, ".")
        message.sub!(/^The property /, "The parameter ")
        message
      end

      def run_capistrano
        args = ["bundle", "exec", "cap"]
        if @options[:trace]
          args << "-t"
        end
        args.concat(["production", "setup"])
        Dir.chdir("#{ROOT}/commands/setup") do
          system(*args)
        end
      end

      def report_success
        puts
        puts "-------------------------------------"
        puts Paint["#{success_greeting}, setup succeeded! :-D", :green]
      end

      def report_failure
        puts
        puts "-------------------------------------"
        puts Paint["Setup failed! :-(", :red]
        puts
        if @options[:ssh_log]
          puts Paint["Please read the SSH log file to find out what went wrong.", :red]
        else
          puts Paint["Please read the SSH log above to find out what went wrong.", :red]
        end
        if !@options[:detailed_backtraces]
          puts Paint["If you need a detailed backtrace, pass --trace.", :red]
        end
        if $?
          exit $?.exitstatus
        else
          exit 1
        end
      end
    end
  end
end

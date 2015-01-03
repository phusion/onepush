require 'optparse'
require 'json'
require 'thread'
require 'time'
require 'etc'
require 'fileutils'
require 'paint'
require 'net/http'
require 'uri'
require_relative '../base'
require_relative './params'
require_relative '../setup/command'
require_relative '../push/command'
require_relative '../open/utils'
require_relative '../../lib/utils/hash_with_indifferent_access'

module Pomodori
  module Commands
    class DeployCommand < Base
      def run
        parse_options
        validate_and_finalize_options
        setup_paint_mode
        setup
        push
        prepare_announcement
        if run_capistrano
          report_success
          print_announcement
        else
          report_failure
        end
      end

    private
      def self.create_default_options
        HashWithIndifferentAccess.new(
          :app_server_addresses => [],
          :ssh_keys  => [],
          :dry_run   => false,
          :push      => true,
          :task      => 'deploy'
        )
      end

      def self.create_option_parser(options)
        OptionParser.new do |opts|
          nl = "\n" + (" " * 37)
          opts.banner = "Usage: pomodori deploy [OPTIONS]"
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
          opts.on("--app-root PATH", String,
            "Path to the application. Default: current#{nl}" +
            "working directory") do |value|
            options[:app_root] = value
          end
          opts.on("--app-server-address ADDRESS", String,
            "The address of an app server to deploy to.#{nl}" +
            "This can be specified multiple times for#{nl}" +
            "setting up multiple servers. The first app#{nl}" +
            "server in the list is considered the#{nl}" +
            "primary; database migrations will run there") do |address|
            options[:app_server_addresses] << address
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

          opts.separator ""
          opts.on("--dry-run", "Do not actually do anything") do
            options[:dry_run] = true
          end
          opts.on("--no-push", "Do not push Git before deploying") do
            options[:push] = false
          end
          opts.on("--task NAME", String, "Internal task to execute. Default: deploy") do |value|
            options[:task] = value
          end
          opts.on("--trace", "-t", "Show detailed backtraces and trace tasks") do
            options[:trace] = true
          end
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

        maybe_load_default_config_files(@options[:app_root])

        begin
          @app_config = AppConfig.new(@options.delete(:app_config) || @options)
        rescue ArgumentError => e
          abort(" *** ERROR: " + AppConfig.fixup_error_message(e.message))
        end

        begin
          @params = DeployParams.new(@options)
          @params.app_config = @app_config
        rescue ArgumentError => e
          abort(" *** ERROR: " + fixup_params_error_message(e.message))
        end

        @params.if_needed = true
        @params.validate_and_finalize!
        @app_config.set_defaults!(@params)
      end

      def autodetect_language_specific_params(params)
        app_root = params.app_root

        case params.app_config.language
        when 'ruby'
          gemfile = "#{app_root}/Gemfile"
          if !params.key?(:bundler)
            params.bundler = File.exist?(gemfile)
          end
          if !params.key?(:rails)
            params.rails =
              (File.exist?(gemfile) || File.read(gemfile) =~ /rails/) &&
              File.exist?("#{app_root}/config/environment.rb")
          end
        end
      end

      def fixup_params_error_message(message)
        # Example message:
        # The property 'domain_names' is required for Pomodori::AppConfig.
        message = message.sub(/ for (.+?)$/, ".")
        message.sub!(/^The property /, "The parameter ")
        message
      end

      def setup
        if @options[:dry_run]
          puts "Dry running, skipping setup."
        else
          SetupCommand.new([
            "--config-json", JSON.generate(@params),
            "--progress-ceil", "0.45",
            "--if-needed",
            "--no-announcements"
          ]).run
        end
      end

      def push
        if @options[:push]
          notice "Pushing code to server..."
          if @options[:dry_run]
            puts "Dry running, skipping push."
          else
            PushCommand.new([
              "--config-json", JSON.generate(@params),
              "--app-root", @params.app_root
            ]).run
            if @params.progress
              report_progress 0.55
            end
          end
        end
      end

      def run_capistrano
        if @options[:dry_run]
          puts "Dry running, skipping deploy."
          true
        else
          @params.progress_base = 0.55
          ENV["POMODORI_PARAMS"] = JSON.generate(@params)
          args = ["bundle", "exec", "cap"]
          if @options[:trace]
            args << "-t"
          end
          args.concat(["production", @options[:task]])
          Dir.chdir("#{ROOT}/commands/deploy/#{@app_config.type}") do
            system(*args)
          end
        end
      end

      def report_success
        puts
        puts "-------------------------------------"
        puts Paint["#{success_greeting}, deploy succeeded! :-D", :green]
        puts

        utils = OpenUtils.new(@params)
        puts " * You now can access your app by running '" + Paint["pomodori open", :bold] + "'."
        if !utils.app_dns_resolves_to_one_of_app_servers?
          puts " * It seems you haven't setup DNS records for your servers yet! Please don't"
          puts "   forget to do that at some point. 'pomodori open' works even when you haven't"
          puts "   configured DNS yet."
        else
          puts " * Or access your app at: #{utils.public_url}"
        end
        if utils.using_amazon_ec2?
          puts " * You are on Amazon EC2. Please don't forget to configure your EC2 Security"
          puts "   Groups and " + Paint["ensuring that port 80 (HTTP) is accessible.", :bold]
        end
      end

      def report_failure
        puts
        puts "-------------------------------------"
        puts Paint["Deploy failed! :-(", :red]
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

require 'optparse'
require 'json'
require 'paint'
require_relative '../base'
require_relative '../setup/params'
require_relative '../../lib/constants'
require_relative '../../lib/utils/hash_with_indifferent_access'

module Pomodori
  module Commands
    class PushCommand < Base
      def run
        parse_options
        maybe_load_default_config_files
        validate_and_finalize_options
        setup_paint_mode
        git_urls.each_with_index do |url, i|
          puts if i != 0
          puts Paint["Pushing to #{url}...", :bold]
          if !system("git", "push", url, "#{current_revision}:master", "-f")
            abort " *** ERROR: push failed"
          end
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

      def git_urls
        username = @app_config.user
        path = "/etc/pomodori/apps/#{@params.app_id}/pomodori_repo"
        @params.app_server_addresses.map do |address|
          address = address.sub(/.*?@/, "")
          "ssh://#{username}@#{address}#{path}"
        end
      end

      def current_revision
        @current_revision ||= `git rev-parse --abbrev-ref HEAD`.strip
      end
    end
  end
end

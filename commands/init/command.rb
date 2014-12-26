require 'optparse'
require 'stringio'
require 'etc'
require_relative '../base'
require_relative '../../lib/constants'

module Pomodori
  module Commands
    class InitCommand < Base
      def run
        parse_options
        check_file_not_exists
        generate_config
        modify_gemfile
      end

    private
      def self.create_option_parser(options)
        OptionParser.new do |opts|
          nl = "\n" + (" " * 37)
          opts.banner = "Usage: pomodori init [APP ROOT]"
          opts.separator "Generate an initial Pomodori config file."
          opts.separator ""

          opts.separator "Options:"
          opts.on("--force", "Overwrite existing Pomodori config file") do
            options[:force] = true
          end
          opts.on("--help", "Show this help") do
            options[:help] = true
          end
        end
      end

      def parse_options
        super
        if @argv.size == 0
          @app_root = Dir.pwd
        elsif @argv.size == 1
          @app_root = File.absolute_path(@argv[0])
        else
          abort " *** ERROR: you may specify at most one application root. Please refer to --help."
        end
      end

      def check_file_not_exists
        if !@options[:force] && File.exist?("#{@app_root}/pomodori.json")
          abort " *** ERROR: #{@app_root}/pomodori.json already exists."
        end
      end

      def generate_config
        io = StringIO.new
        io.puts %Q{    // A unique identifier for your app. Once you've run a}
        io.puts %Q{    // 'setup' or 'deploy', do not change this ID!}
        io.puts %Q{    "app_id": #{app_id.inspect},}
        io.puts
        io.puts %Q{    // Host name(s) that your app listens on, in Nginx}
        io.puts %Q{    // server_name format.}
        io.puts %Q{    "domain_names": #{domain_names.inspect},}
        io.puts
        io.puts %Q{    // Which server do you want to deploy your app to? Enter}
        io.puts %Q{    // its SSH login info here. It must either be the root user,}
        io.puts %Q{    // or a user with passwordless sudo access.}
        io.puts %Q{    "server_address": "root@your-server.com",}
        io.puts %Q{    // Uncomment if the above address is a Vagrant VM. Will}
        io.puts %Q{    // use the Vagrant insecure SSH key for SSH authentication.}
        io.puts %Q{    //"vagrant_key": true,}
        io.puts

        case detect_language
        when "ruby"
          io.puts %Q{    "language": "ruby",}
          io.puts %Q{    "ruby_version": "#{DEFAULT_RUBY_VERSION}",}
          if rails?
            io.puts %Q{    "rails": true,}
          end
        when "nodejs"
          io.puts %Q{    "language": "nodejs",}
          io.puts %Q{    "nodejs_version": "#{DEFAULT_NODEJS_VERSION}",}
        end

        io.puts
        io.puts %Q{    // Uncomment this if you use Redis.}
        io.puts %Q{    //"redis": true,}
        io.puts %Q{    // Uncomment this if you use memcached.}
        io.puts %Q{    //"memcached": true,}
        io.puts
        io.puts %Q{    // Specify the SSH keys of users who are allowed to deploy}
        io.puts %Q{    // new releases of the app.}
        io.puts %Q{    "deployment_ssh_keys": [}
        if default_ssh_key
          io.puts %Q{        // #{developer_name}}
          io.puts %Q{        #{default_ssh_key.inspect}}
        end
        io.puts %Q{    ]}

        File.open("#{@app_root}/pomodori.json", "w") do |f|
          f.puts '{'
          f.puts io.string.sub(/,[\r\n]*\Z/, '')
          f.puts '}'
        end
        puts "Generated #{@app_root}/pomodori.json"
      end

      def modify_gemfile
        if detect_language == "ruby"
          contents = File.read(gemfile)
          if contents !~ /'pg'/ && contents !~ /"pg"/
            File.open(gemfile, "a") do |f|
              f.puts
              f.puts %Q{gem "pg"}
            end
            puts
            puts "NOTICE: #{POMODORI_APP_NAME} requires PostgreSQL, so the 'pg' gem " +
              "has been added to your Gemfile. Please run 'bundle install'."
          end
        end
      end

      def app_id
        @app_id ||= File.basename(@app_root)
      end

      def domain_names
        ".#{@app_id}.com"
      end

      def detect_language
        if File.exist?(gemfile)
          "ruby"
        elsif File.exist?(package_json)
          abort "Node.js is not yet supported."
        end
      end

      def gemfile
        @gemfile ||= "#{@app_root}/Gemfile"
      end

      def rails?
        File.read(gemfile) =~ /rails/ &&
          File.exist?("#{@app_root}/config/environment.rb")
      end

      def package_json
        @package_json ||= "#{@app_root}/package.json"
      end

      def default_ssh_key
        return @default_ssh_key if defined?(@default_ssh_key)
        @default_ssh_key = try_read_files("~/.ssh/id_rsa.pub", "~/.ssh/id_dsa.pub")
      end

      def try_read_files(*paths)
        paths.each do |path|
          path = File.expand_path(path)
          if File.exist?(path)
            return File.read(path).strip
          end
        end
        return nil
      end

      def developer_name
        if git_user_name
          if git_user_email
            "#{git_user_name} (#{git_user_email})"
          else
            git_user_name
          end
        else
          Etc.getpwuid.name
        end
      end

      def git_user_name
        return @git_user_name if defined?(@git_user_name)
        begin
          result = `git config user.name`.strip
        rescue Errno::ENOENT
          @git_user_name = nil
        else
          if result.empty?
            @git_user_name = nil
          else
            @git_user_name = result
          end
        end
      end

      def git_user_email
        return @git_user_email if defined?(@git_user_email)
        begin
          result = `git config user.email`.strip
        rescue Errno::ENOENT
          @git_user_email = nil
        else
          if result.empty?
            @git_user_email = nil
          else
            @git_user_email = result
          end
        end
      end
    end
  end
end

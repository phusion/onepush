require 'json'
require 'stringio'
require 'securerandom'
require 'shellwords'
require 'net/http'
require 'net/https'
require_relative '../../lib/config'
require_relative '../../lib/version'

fatal_and_abort "Please set the CONFIG_FILE environment variable" if !ENV['CONFIG_FILE']
CONFIG = JSON.parse(File.read(ENV['CONFIG_FILE']))

check_config_requirements(CONFIG)
Flippo.set_config_defaults(CONFIG)


def install_language_runtime
  case CONFIG['type']
  when 'ruby'
    invoke :install_ruby_runtime
    install_common_ruby_app_dependencies
  end
end

task :install_ruby_runtime do
  case CONFIG['ruby_manager']
  when 'rvm'
    install_rvm
  end
end

def install_rvm
  on roles(:app) do
    if !test("[[ -e /usr/local/rvm/bin/rvm ]]")
      execute(b "curl -sSL https://get.rvm.io | sudo -H bash -s stable --ruby")
    end
  end
end

def install_common_ruby_app_dependencies
  if CONFIG['install_common_ruby_app_dependencies']
    on roles(:app) do |host|
      case host.properties.fetch(:os_class)
      when :redhat
        raise "TODO"
      when :debian
        packages = []
        # For Rails.
        packages.concat %w(nodejs)
        # For Nokogiri.
        packages.concat %w(libxml2-dev libxslt1-dev)
        # For rmagick and minimagick.
        packages.concat %w(imagemagick libmagickwand-dev)
        # For mysql and mysql2.
        packages.concat %w(libmysqlclient-dev)
        # For sqlite3.
        packages.concat %w(libsqlite3-dev)
        # For postgres and pg.
        packages.concat %w(libpq-dev)
        # For capybara-webkit.
        packages.concat %w(libqt4-webkit libqt4-dev)
        # For curb.
        packages.concat %w(libcurl4-openssl-dev)

        apt_get_install(host, packages)
      else
        raise "Bug"
      end
    end
  end
end

def create_user(name)
  on roles(:app) do
    if !test("id -u #{name}")
      execute "adduser", "--disabled-password", "--gecos", name, name
    end
    case CONFIG['type']
    when 'ruby'
      case CONFIG['ruby_manager']
      when 'rvm'
        execute "usermod -a -G rvm #{name}"
      end
    end
  end
end

def create_app_dir(path, owner)
  primary_dirs = "#{path} #{path}/releases #{path}/shared #{path}/flippo_repo"
  on roles(:app) do
    execute "mkdir -p #{primary_dirs} && chown #{owner}: #{primary_dirs} && chmod u=rwx,g=rx,o=x #{primary_dirs}"
    execute "mkdir -p #{path}/shared/config && chown #{owner}: #{path}/shared/config"
    execute "cd #{path}/flippo_repo && if ! [[ -e HEAD ]]; then sudo -u #{owner} -H git init --bare; fi"
  end
end

def install_dbms(type)
  on roles(:db) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      case type
      when 'postgresql'
        raise "TODO"
      else
        abort "Unsupported database type. Only PostgreSQL is supported."
      end
    when :debian
      case type
      when 'postgresql'
        apt_get_install(host, %w(postgresql postgresql-client))
      else
        abort "Unsupported database type. Only PostgreSQL is supported."
      end
    else
      raise "Bug"
    end
  end

  on roles(:app) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      case type
      when 'postgresql'
        raise "TODO"
      else
        abort "Unsupported database type. Only PostgreSQL is supported."
      end
    when :debian
      case type
      when 'postgresql'
        apt_get_install(host, %w(libpq-dev))
      else
        abort "Unsupported database type. Only PostgreSQL is supported."
      end
    else
      raise "Bug"
    end
  end
end

def setup_database(type, name, user)
  on roles(:db) do
    case type
    when 'postgresql'
      user_test_script = "cd / && sudo -u postgres -H psql postgres -tAc " +
        "\"SELECT 1 FROM pg_roles WHERE rolname='#{user}'\" | grep -q 1"
      if !test(b user_test_script)
        execute("cd / && sudo -u postgres -H createuser --no-password #{user}")
      end

      databases = capture(b "cd / && sudo -u postgres -H psql postgres -lqt | cut -d \\| -f 1")
      if databases !~ /^ *#{Regexp.escape name} *$/
        execute("cd / && sudo -u postgres -H createdb --no-password --owner #{user} #{name}")
      end
    else
      abort "Unsupported database type. Only PostgreSQL is supported."
    end
  end
end

def create_app_database_config(app_dir, owner, db_type, db_name, db_user)
  on roles(:app) do
    if !test("[[ -e #{app_dir}/shared/config/database.yml ]]")
      config = StringIO.new
      config.puts "default_settings: &default_settings"
      case db_type
      when 'postgresql'
        config.puts "  adapter: postgresql"
      else
        abort "Unsupported database type . Only PostgreSQL is supported."
      end
      config.puts "  host: localhost"
      config.puts "  database: #{db_name}"
      config.puts "  username: #{db_user}"
      config.puts "  encoding: utf-8"
      config.puts "  pool: 5"
      config.puts
      ["development", "staging", "production"].each do |env|
        config.puts "#{env}:"
        config.puts "  <<: *default_settings"
        config.puts
      end
      config.rewind
      upload! config, "#{app_dir}/shared/config/database.yml"
    end

    if !test("[[ -e #{app_dir}/shared/config/secrets.yml ]]")
      config = StringIO.new
      config.puts "default_settings: &default_settings"
      config.puts "  secret_key_base: #{SecureRandom.hex(64)}"
      config.puts
      ["development", "staging", "production"].each do |env|
        config.puts "#{env}:"
        config.puts "  <<: *default_settings"
        config.puts
      end
      config.rewind
      upload! config, "#{app_dir}/shared/config/secrets.yml"
    end

    execute "cd #{app_dir}/shared/config && " +
      "chmod 600 database.yml secrets.yml && " +
      "chown #{owner}: database.yml secrets.yml"
  end
end

def install_flippo_manifest(name, app_dir)
  config = StringIO.new
  config.puts JSON.dump(CONFIG)
  config.rewind

  on roles(:app) do
    upload! config, "#{app_dir}/flippo-setup.json"
    execute "chown root: #{app_dir}/flippo-setup.json && " +
      "chmod 600 #{app_dir}/flippo-setup.json"
    execute "mkdir -p /etc/flippo/apps && " +
      "cd /etc/flippo/apps && " +
      "rm -f #{name} && " +
      "ln -s #{app_dir} #{name}"
  end

  on roles(:app, :db) do
    execute "mkdir -p /etc/flippo/setup && " +
      "cd /etc/flippo/setup && " +
      "date +%s > last_run_time && " +
      "echo #{Flippo::VERSION_STRING} > last_run_version"
  end
end

task :restart_services => :autodetect_os do
  on roles(:app) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      raise "TODO"
    when :debian
      case CONFIG['web_server_type']
      when 'nginx'
        if test("[[ -e /var/run/flippo/restart_web_server ]]")
          execute "rm -f /var/run/flippo/restart_web_server"
          if test("[[ -e /etc/init.d/nginx ]]")
            execute "/etc/init.d/nginx restart"
          elsif test("[[ -e /etc/service/nginx ]]")
            execute "sv restart /etc/service/nginx"
          end
        end
      when 'apache'
        execute(
          "if [[ -e /var/run/flippo/restart_web_server ]]; then " +
            "rm -f /var/run/flippo/restart_web_server && service apache2 restart; " +
          "fi")
      else
        abort "Unsupported web server. Flippo supports 'nginx' and 'apache'."
      end
    else
      raise "Bug"
    end
  end
end

desc "Setup the server environment"
task :setup do
  invoke :autodetect_os
  invoke :install_essentials
  install_language_runtime
  invoke :install_passenger
  invoke :install_web_server
  create_user(CONFIG['user'])
  create_app_dir(CONFIG['app_dir'], CONFIG['user'])
  install_dbms(CONFIG['database_type'])
  setup_database(CONFIG['database_type'], CONFIG['database_name'],
    CONFIG['database_user'])
  create_app_database_config(CONFIG['app_dir'], CONFIG['user'],
    CONFIG['database_type'], CONFIG['database_name'],
    CONFIG['database_user'])
  install_flippo_manifest(CONFIG['name'], CONFIG['app_dir'])
  invoke :restart_services
end

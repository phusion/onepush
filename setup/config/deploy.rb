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


def apt_get_update(host)
  execute "apt-get update && touch /var/lib/apt/periodic/update-success-stamp"
  host.add_property(:apt_get_updated, true)
end

def apt_get_install(host, packages)
  packages = filter_non_installed_packages(host, packages)
  if !packages.empty?
    if !host.properties.fetch(:apt_get_updated)
      two_days = 2 * 60 * 60 * 24
      script = "[[ -e /var/lib/apt/periodic/update-success-stamp ]] && " +
        "timestamp=`stat -c %Y /var/lib/apt/periodic/update-success-stamp` && " +
        "threshold=`date +%s` && " +
        "(( threshold = threshold - #{two_days} )) && " +
        '[[ "$timestamp" -gt "$threshold" ]]'
      if !test(script)
        apt_get_update(host)
      end
    end
    execute "apt-get install -y #{packages.join(' ')}"
  end
end

def check_packages_installed(host, names)
  case host.properties.fetch(:os_class)
  when :redhat
    raise "TODO"
  when :debian
    result = {}
    installed = capture("dpkg-query -s #{names.join(' ')} | grep '^Package: ' 2>/dev/null")
    installed = installed.gsub(/^Package: /, '').split("\n")
    names.each do |name|
      result[name] = installed.include?(name)
    end
    result
  else
    raise "Bug"
  end
end

def filter_non_installed_packages(host, names)
  result = []
  check_packages_installed(host, names).each_pair do |name, installed|
    if !installed
      result << name
    end
  end
  result
end

def b(script)
  full_script = "set -o pipefail && #{script}"
  "/bin/bash -c #{Shellwords.escape(full_script)}"
end

def autodetect_os
  on roles(:app, :db) do |host|
    if test("[[ -e /etc/redhat-release || -e /etc/centos-release ]]")
      host.set(:os_class, :redhat)
      info "Red Hat or CentOS detected"
    elsif test("[[ -e /etc/system-release ]]") && capture("/etc/system-release") =~ /Amazon/
      host.set(:os_class, :redhat)
      info "Amazon Linux detected"
    elsif test("[[ -e /usr/bin/apt-get ]]")
      # We don't use /etc/debian_version or things like that because
      # it's not always installed.
      host.set(:os_class, :debian)
      info "Debian or Ubuntu detected"
    else
      abort "Unsupported server operating system. Flippo only supports Red Hat, CentOS, Amazon Linux, Debian and Ubuntu"
    end
  end
end

def install_essentials
  on roles(:app) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      execute "yum install -y git sudo curl gcc g++ make"
    when :debian
      apt_get_install(host, %w(git sudo curl apt-transport-https ca-certificates lsb-release build-essential))
    else
      raise "Bug"
    end
  end

  on roles(:db) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      execute "yum install -y sudo"
    when :debian
      apt_get_install(host, %w(sudo apt-transport-https ca-certificates lsb-release))
    else
      raise "Bug"
    end
  end
end

def install_language_runtime
  case CONFIG['type']
  when 'ruby'
    case CONFIG['ruby_manager']
    when 'rvm'
      install_rvm
    end
    install_common_ruby_app_dependencies
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

def install_passenger_and_web_server
  if CONFIG['install_passenger']
    on roles(:app) do |host|
      case host.properties.fetch(:os_class)
      when :redhat
        install_passenger_from_source
        install_web_server_with_passenger_from_source
      when :debian
        codename = capture(b "lsb_release -c | awk '{ print $2 }'").strip
        if passenger_apt_repo_available?(codename)
          install_passenger_and_web_server_from_apt(host, codename)
        else
          install_passenger_from_source
          install_web_server_with_passenger_from_source
        end
      else
        raise "Bug"
      end
    end
  end
end

def install_passenger_and_web_server_from_apt(host, codename)
  if !test("[[ -e /etc/apt/sources.list.d/passenger.list ]]")
    config = StringIO.new
    if CONFIG['passenger_enterprise']
      config.puts "deb https://download:#{CONFIG['passenger_enterprise_download_token']}@" +
        "www.phusionpassenger.com/enterprise_apt #{codename} main"
    else
      config.puts "deb https://oss-binaries.phusionpassenger.com/apt/passenger #{codename} main"
    end
    config.rewind
    upload! config, "/etc/apt/sources.list.d/passenger.list"
    execute "apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 561F9B9CAC40B2F7"
    apt_get_update(host)
  end
  execute "chmod 600 /etc/apt/sources.list.d/passenger.list"

  if CONFIG['install_web_server']
    case CONFIG['web_server_type']
    when 'nginx'
      apt_get_install(host, %w(nginx-extras passenger))
      md5 = capture("md5sum /etc/nginx/nginx.conf")
      execute "sed -i 's|# passenger_root|passenger_root|' /etc/nginx/nginx.conf"
      execute "sed -i 's|# passenger_ruby|passenger_ruby|' /etc/nginx/nginx.conf"

      # Restart Nginx if config changed.
      if capture("md5sum /etc/nginx/nginx.conf") != md5
        execute "service nginx restart"
      end
    when 'apache'
      apt_get_install(host, "libapache2-mod-passenger")
      if !test("[[ -e /etc/apache2/mods-enabled/passenger.load ]]")
        execute "a2enmod passenger && service apache2 restart"
      end
    else
      abort "Unsupported web server. Flippo supports 'nginx' and 'apache'."
    end
  end
end

def install_passenger_from_source
  # This should be separated to its own project. A Passenger Version Manager or something.
  raise "TODO"
end

def install_web_server_with_passenger_from_source
  raise "TODO"
end

def passenger_apt_repo_available?(codename)
  http = Net::HTTP.new("oss-binaries.phusionpassenger.com", 443)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER
  response = http.request(Net::HTTP::Head.new("/apt/passenger/dists/#{codename}/Release"))
  response.code == "200"
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

desc "Setup the server environment"
task :setup do
  autodetect_os
  install_essentials
  install_language_runtime
  install_passenger_and_web_server
  create_user(CONFIG['user'])
  create_app_dir(CONFIG['app_dir'], CONFIG['user'])
  install_dbms(CONFIG['database_type'])
  setup_database(CONFIG['database_type'], CONFIG['database_name'],
    CONFIG['database_user'])
  create_app_database_config(CONFIG['app_dir'], CONFIG['user'],
    CONFIG['database_type'], CONFIG['database_name'],
    CONFIG['database_user'])
  install_flippo_manifest(CONFIG['name'], CONFIG['app_dir'])
end

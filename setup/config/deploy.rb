require 'json'
require 'shellwords'
require 'net/http'
require 'net/https'
require_relative '../../lib/config'

fatal_and_abort "Please set the CONFIG_FILE environment variable" if !ENV['CONFIG_FILE']
CONFIG = JSON.parse(File.read(ENV['CONFIG_FILE']))
SYSINFO = {}


# TODO: set default values in CONFIG itself so that when dumping the manifest,
# all values are set.
Flippo.set_config_defaults(CONFIG)
check_config_requirements(CONFIG)

set :name, CONFIG['name'] || fatal_and_abort("The 'name' option must be set")
set :type, CONFIG['type'] || fatal_and_abort("The 'type' option must be set")

set :user, CONFIG['user'] || fetch(:name)
set :app_dir, CONFIG['app_dir'] || "/var/www/#{fetch:name}"

set :database_type, CONFIG['database_type'] || 'postgresql'
set :database_name, CONFIG['database_name'] || fetch(:name)
set :database_user, fetch(:user)

set :setup_web_server, CONFIG.fetch('setup_web_server', true)

set :ruby_manager, CONFIG['ruby_manager'] || 'rvm'
set :web_server_type, CONFIG['web_server_type'] || 'nginx'

set :passenger_enterprise, CONFIG.fetch('passenger_enterprise', false)
set :passenger_enterprise_download_token, CONFIG['passenger_enterprise_download_token']
if fetch(:passenger_enterprise) && !fetch(:passenger_enterprise_download_token)
  fatal_and_abort "If you set passenger_enterprise to true, then you must also set passenger_enterprise_download_token"
end


def apt_get_update
  execute "apt-get update && date +%s > /var/lib/apt/periodic/update-success-stamp"
  SYSINFO[:apt_updated] = true
end

def apt_get_install(packages)
  if !SYSINFO[:apt_updated]
    #::File.exists?('/var/lib/apt/periodic/update-success-stamp') &&
    #::File.mtime('/var/lib/apt/periodic/update-success-stamp') > Time.now - 86400*2
    script = "[[ -e /var/lib/apt/periodic/update-success-stamp ]] && " +
      "timestamp=`stat -c %Y /var/lib/apt/periodic/update-success-stamp` && " +
      "threshold=`date +%s` && " +
      "(( threshold = threshold - 86400 * 2 )) && " +
      '[[ "$timestamp" -gt "$threshold" ]]'
    if !test(script)
      apt_get_update
    end
  end
  execute "apt-get install -y #{packages}"
end

def b(script)
  full_script = "set -o pipefail && #{script}"
  "/bin/bash -c #{Shellwords.escape(full_script)}"
end

def autodetect_os
  on roles(:app) do
    if test("[[ -e /etc/redhat-release || -e /etc/centos-release ]]")
      SYSINFO[:os_class] = :redhat
      info "Red Hat or CentOS detected"
    elsif test("[[ -e /etc/system-release ]]") && capture("/etc/system-release") =~ /Amazon/
      SYSINFO[:os_class] = :redhat
      info "Amazon Linux detected"
    elsif test("[[ -e /usr/bin/apt-get ]]")
      # We don't use /etc/debian_version or things like that because
      # it's not always installed.
      SYSINFO[:os_class] = :debian
      info "Debian or Ubuntu detected"
    else
      abort "Unsupported server operating system. Flippo only supports Red Hat, CentOS, Amazon Linux, Debian and Ubuntu"
    end
  end
end

def install_essentials
  on roles(:app) do
    case SYSINFO[:os_class]
    when :redhat
      execute "yum install -y git sudo curl gcc g++ make"
    when :debian
      apt_get_install "git sudo curl apt-transport-https ca-certificates lsb-release build-essential"
    else
      raise "Bug"
    end
  end
end

def install_language_runtime
  case fetch(:type)
  when 'ruby'
    case fetch(:ruby_manager)
    when 'rvm'
      install_rvm
    end
  end
end

def install_rvm
  on roles(:app) do
    if !test("[[ -e /usr/local/rvm/bin/rvm ]]")
      execute(b "curl -sSL https://get.rvm.io | sudo -H bash -s stable --ruby")
    end
  end
end

def install_passenger_and_web_server
  on roles(:app) do
    case SYSINFO[:os_class]
    when :redhat
      install_passenger_from_source
      install_web_server_with_passenger_from_source
    when :debian
      codename = capture(b "lsb_release -c | awk '{ print $2 }'").strip
      if passenger_apt_repo_available?(codename)
        install_passenger_and_web_server_from_apt(codename)
      else
        install_passenger_from_source
        install_web_server_with_passenger_from_source
      end
    else
      raise "Bug"
    end
  end
end

def install_passenger_and_web_server_from_apt(codename)
  if !test("[[ -e /etc/apt/sources.list.d/passenger.list ]]")
    config = StringIO.new
    if fetch(:passenger_enterprise)
      config.puts "deb https://download:#{fetch(:passenger_enterprise_download_token)}@" +
        "www.phusionpassenger.com/enterprise_apt #{codename} main"
    else
      config.puts "deb https://oss-binaries.phusionpassenger.com/apt/passenger #{codename} main"
    end
    config.rewind
    upload! config, "/etc/apt/sources.list.d/passenger.list"
    execute "apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 561F9B9CAC40B2F7"
    apt_get_update
  end
  execute "chmod 600 /etc/apt/sources.list.d/passenger.list"

  if fetch(:setup_web_server)
    case fetch(:web_server_type)
    when 'nginx'
      apt_get_install "nginx-extras passenger"
      md5 = capture("md5sum /etc/nginx/nginx.conf")
      execute "sed -i 's|# passenger_root|passenger_root|' /etc/nginx/nginx.conf"
      execute "sed -i 's|# passenger_ruby|passenger_ruby|' /etc/nginx/nginx.conf"

      # Restart Nginx if config changed.
      if capture("md5sum /etc/nginx/nginx.conf") != md5
        execute "service nginx restart"
      end
    when 'apache'
      apt_get_install "libapache2-mod-passenger"
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
    case fetch(:type)
    when 'ruby'
      case fetch(:ruby_manager)
      when 'rvm'
        execute "usermod -a -G rvm #{name}"
      end
    end
  end
end

def create_app_dir(path, owner)
  primary_dirs = "#{path} #{path}/releases #{path}/shared #{path}/repo"
  on roles(:app) do
    execute "mkdir -p #{primary_dirs} && chown #{owner}: #{primary_dirs} && chmod u=rwx,g=rx,o=x #{primary_dirs}"
    execute "mkdir -p #{path}/shared/config && chown #{owner}: #{path}/shared/config"
    execute "cd #{path}/repo && if ! [[ -e HEAD ]]; then sudo -u #{owner} -H git init --bare; fi"
  end
end

def install_dbms(type)
  on roles(:app) do
    case SYSINFO[:os_class]
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
        apt_get_install "postgresql postgresql-client libpq-dev"
      else
        abort "Unsupported database type. Only PostgreSQL is supported."
      end
    else
      raise "Bug"
    end
  end
end

def setup_database(type, name, user)
  on roles(:app) do
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
    execute "chown #{owner}: #{app_dir}/shared/config/database.yml"
    execute "chmod 600 #{app_dir}/shared/config/database.yml"
  end
end

def install_flippo_manifest(name, app_dir)
  config = StringIO.new
  config.puts JSON.dump(CONFIG)
  config.rewind

  on roles(:app) do
    upload! config, "#{app_dir}/flippo.json"
    execute "chown root: #{app_dir}/flippo.json && " +
      "chmod 600 #{app_dir}/flippo.json"
    execute "mkdir -p /etc/flippo && " +
      "cd /etc/flippo && " +
      "rm -f #{name} && " +
      "ln -s #{app_dir} #{name}"
  end
end

desc "Setup the server environment"
task :setup do
  autodetect_os
  install_essentials
  install_language_runtime
  install_passenger_and_web_server
  create_user(fetch(:user))
  create_app_dir(fetch(:app_dir), fetch(:user))
  install_dbms(fetch(:database_type))
  setup_database(fetch(:database_type), fetch(:database_name),
    fetch(:database_user))
  create_app_database_config(fetch(:app_dir), fetch(:user),
    fetch(:database_type), fetch(:database_name),
    fetch(:database_user))
  install_flippo_manifest(fetch(:name), fetch(:app_dir))
end

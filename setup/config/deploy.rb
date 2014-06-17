require 'json'
require 'shellwords'

abort "Please set the CONFIG_FILE environment variable" if !ENV['CONFIG_FILE']
CONFIG = JSON.parse(File.read(ENV['CONFIG_FILE']))
SYSINFO = {}

set :name, CONFIG['name'] || abort("The 'name' option must be set")
set :type, CONFIG['type'] || abort("The 'type' option must be set")
set :user, CONFIG['user'] || fetch(:name)
set :app_dir, CONFIG['app_dir'] || "/var/www/#{fetch:name}"
set :database_type, CONFIG['database_type'] || 'postgresql'
set :database_name, CONFIG['database_name'] || fetch(:name)
set :database_user, fetch(:user)
set :ruby_manager, CONFIG['ruby_manager'] || 'rvm'

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
      execute "apt-get update && date +%s > /var/lib/apt/periodic/update-success-stamp"
      SYSINFO[:apt_updated] = true
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
      puts "Red Hat or CentOS detected"
    elsif test("[[ -e /etc/system-release ]]") && capture("/etc/system-release") =~ /Amazon/
      SYSINFO[:os_class] = :redhat
      puts "Amazon Linux detected"
    elsif test("[[ -e /usr/bin/apt-get ]]")
      # We don't use /etc/debian_version or things like that because
      # it's not always installed.
      SYSINFO[:os_class] = :debian
      puts "Debian or Ubuntu detected"
    else
      abort "Unsupported server operating system. Flippo only supports Red Hat, CentOS, Amazon Linux, Debian and Ubuntu"
    end
  end
end

def install_essentials
  on roles(:app) do
    case SYSINFO[:os_class]
    when :redhat
      execute "yum install -y git sudo curl ca-certificates gcc g++ make"
    when :debian
      apt_get_install "git sudo curl build-essential"
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

def install_passenger
  on roles(:app) do
    
  end
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

desc "Setup the server environment"
task :setup do
  autodetect_os
  install_essentials
  install_language_runtime
  install_passenger
  create_user(fetch(:user))
  create_app_dir(fetch(:app_dir), fetch(:user))
  install_dbms(fetch(:database_type))
  setup_database(fetch(:database_type), fetch(:database_name),
    fetch(:database_user))
  create_app_database_config(fetch(:app_dir), fetch(:user),
    fetch(:database_type), fetch(:database_name),
    fetch(:database_user))
end

require 'yaml'
require 'thread'
require 'securerandom'
require 'shellwords'

task :install_dbms => :install_essentials do
  if PARAMS.manage_database_system?
    log_notice "Installing database server software..."
    type = APP_CONFIG.database_type

    on roles(:db) do |host|
      case host.properties.fetch(:os_class)
      when :redhat
        case type
        when 'postgresql'
          # TODO: install hstore (maybe in some contrib package)
          yum_install(host, %w(postgresql postgresql-server))
          files = sudo_capture(host, "ls -1 /var/lib/pgsql/data")
          if files.empty?
            sudo(host, "service postgresql initdb")
          end
          if !sudo_test(host, "service postgresql status")
            sudo(host, "service postgresql start")
            # Wait for PostgreSQL to start.
            sleep 1
          end
        else
          abort "Unsupported database type. Only PostgreSQL is supported."
        end
      when :debian
        case type
        when 'postgresql'
          apt_get_install(host, %w(postgresql postgresql-contrib postgresql-client))
        else
          abort "Unsupported database type. Only PostgreSQL is supported."
        end
      else
        raise "Bug"
      end
    end
  end
end

task :install_database_client_software => :install_essentials do
  if APP_CONFIG.database
    log_notice "Installing database client software..."
    type = APP_CONFIG.database_type

    on roles(:app) do |host|
      case host.properties.fetch(:os_class)
      when :redhat
        case type
        when 'postgresql'
          yum_install(host, %w(postgresql postgresql-devel))
        else
          abort "Unsupported database type. Only PostgreSQL is supported."
        end
      when :debian
        case type
        when 'postgresql'
          apt_get_install(host, %w(postgresql-client libpq-dev))
        else
          abort "Unsupported database type. Only PostgreSQL is supported."
        end
      else
        raise "Bug"
      end
    end
  end
end

task :create_database_password => :install_essentials do
  if PARAMS.manage_database_system?
    log_info "Querying database password..."
    pwpath   = "/etc/pomodori/dbpasswords/#{PARAMS.app_id}"
    password = nil

    on primary(:db) do |host|
      if sudo_test(host, "[[ -e #{pwpath} ]]")
        password = sudo_download_to_string(host, pwpath).strip
      end
    end

    if password.nil?
      log_info "Creating new database password..."
      password = SecureRandom.base64(18)
      io = StringIO.new
      io.puts password
      io.rewind

      on primary(:db) do |host|
        sudo(host, "mkdir -p /etc/pomodori/dbpasswords && " +
          "chmod 700 /etc/pomodori/dbpasswords && " +
          "chown root: /etc/pomodori/dbpasswords")
        sudo_upload(host, io, pwpath,
          :chmod => 600,
          :chown => "root:")
        # The password is important! Don't lose it!
        execute "sync"
      end
    elsif password.empty?
      fatal_and_abort "Unable to query the database password: " +
        "the password file #{pwpath} on #{host} is corrupted."
    end

    set(:database_password, password)
  end
end

task :setup_database => [:install_database_client_software, :create_database_password] do
  if PARAMS.manage_database_system?
    log_notice "Setting up database for app..."
    type   = APP_CONFIG.database_type
    name   = APP_CONFIG.database_name
    user   = APP_CONFIG.database_user
    pwpath = "/etc/pomodori/dbpasswords/#{PARAMS.app_id}"

    on roles(:db) do |host|
      case type
      when 'postgresql'
        user_test_script = "cd / && sudo -u postgres -H psql postgres -tAc " +
          "\"SELECT 1 FROM pg_roles WHERE rolname='#{user}'\" | grep -q 1"
        if !sudo_test(host, user_test_script)
          sudo(host, "cd / && sudo -u postgres -H createuser --no-password -SDR #{user}")
        end
        sudo(host, %Q{sudo -u postgres -H psql <<<"ALTER USER #{name} WITH PASSWORD '`cat #{pwpath}`'"})

        databases = sudo_capture(host, "cd / && sudo -u postgres -H psql postgres -lqt | cut -d \\| -f 1")
        if databases !~ /^ *#{Regexp.escape name} *\r?$/
          sudo(host, "cd / && sudo -u postgres -H createdb --no-password --owner #{user} #{name}")
        end
      else
        abort "Unsupported database type. Only PostgreSQL is supported."
      end
    end
  end
end

def infer_app_database_config(host)
  config = {}

  case APP_CONFIG.database_type
  when 'postgresql'
    config["adapter"] = "postgresql"
  else
    abort "Unsupported database type. Only PostgreSQL is supported."
  end

  if PARAMS.manage_database_system?
    if host != primary(:db)
      config["host"]     = internal_network_route(primary(:db).hostname)
      config["password"] = fetch(:database_password)
    end
    config["database"] = APP_CONFIG.database_name
    config["user"]     = APP_CONFIG.database_user
  else
    config.merge!(PARAMS.external_database)
  end

  config["pool"] = 5
  config["encoding"] = "utf-8"

  config
end

task :create_app_database_config => [:create_app_dir, :create_database_password] do
  if APP_CONFIG.database
    log_notice "Installing database configuration files for app..."
    app_dir = APP_CONFIG.app_dir
    home    = "/home/#{APP_CONFIG.user}"

    on roles(:app) do |host|
      config = infer_app_database_config(host)

      # Generate database.yml.
      io = StringIO.new
      io.puts "# Automatically generated by #{POMODORI_APP_NAME}."
      io.puts "default_settings: &default_settings"
      io.puts YAML.dump("TOP" => config).sub(/.*?TOP:\n/m, "")
      io.puts
      ["development", "staging", "production"].each do |env|
        io.puts "#{env}:"
        io.puts "  <<: *default_settings"
        io.puts
      end
      io.rewind
      sudo_upload(host, io, "#{app_dir}/shared/config/database.yml",
        :chmod => 600,
        :chown => APP_CONFIG.user)

      # Generate database.json.
      io = StringIO.new
      io.puts JSON.pretty_generate(config)
      io.rewind
      sudo_upload(host, io, "#{app_dir}/shared/config/database.json",
        :chmod => 600,
        :chown => APP_CONFIG.user)

      case APP_CONFIG.database_type
      when 'postgresql'
        # Generate database.sh.
        io = StringIO.new
        if config["host"]
          io.puts %Q{PGHOST=#{Shellwords.escape config["host"]}; export PGHOST}
        else
          io.puts "unset PGHOST"
        end
        if config["port"]
          io.puts %Q{PGPORT=#{Shellwords.escape config["port"]}; export PGPORT"}
        else
          io.puts "unset PGPORT"
        end
        io.puts %Q{PGDATABASE=#{Shellwords.escape config["database"]}; export PGDATABASE}
        io.puts %Q{PGUSER=#{Shellwords.escape config["user"]}; export PGUSER}
        ["PGHOSTADDR", "PGPASSFILE"].each do |var|
          io.puts "unset #{var}"
        end
        io.rewind
        sudo_upload(host, io, "#{app_dir}/shared/config/database.sh",
          :chmod => 600,
          :chown => APP_CONFIG.user)

        if host == primary(:db)
          # ~/.pgpass is not necessary.
          sudo(host, "rm -f #{home}/.pgpass")
        else
          # Generate ~/.pgpass.
          io = StringIO.new
          io.puts "# Automatically generated by #{POMODORI_APP_NAME}."
          io.puts [
            config["host"] || "localhost",
            config["port"] || "",
            config["database"],
            config["user"],
            config["password"] || ""
          ].join(":")
          io.rewind
          sudo_upload(host, io, "#{home}/.pgpass",
            :chmod => 600,
            :chown => APP_CONFIG.user)
        end
      end
    end
  end
end

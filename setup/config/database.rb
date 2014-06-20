task :install_dbms => :install_essentials do
  type = SETUP['database_type']

  on roles(:db) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      case type
      when 'postgresql'
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

def setup_database(type, name, user)
  on roles(:db) do |host|
    case type
    when 'postgresql'
      user_test_script = "cd / && sudo -u postgres -H psql postgres -tAc " +
        "\"SELECT 1 FROM pg_roles WHERE rolname='#{user}'\" | grep -q 1"
      if !sudo_test(host, user_test_script)
        sudo(host, "cd / && sudo -u postgres -H createuser --no-password -SDR #{user}")
      end

      databases = sudo_capture(host, "cd / && sudo -u postgres -H psql postgres -lqt | cut -d \\| -f 1")
      if databases !~ /^ *#{Regexp.escape name} *$/
        sudo(host, "cd / && sudo -u postgres -H createdb --no-password --owner #{user} #{name}")
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
      config.puts "# Installed by Onepush."
      config.puts "default_settings: &default_settings"
      case db_type
      when 'postgresql'
        config.puts "  adapter: postgresql"
      else
        abort "Unsupported database type . Only PostgreSQL is supported."
      end
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
      sudo_upload(host, config, "#{app_dir}/shared/config/database.yml")
    end

    if !test("[[ -e #{app_dir}/shared/config/secrets.yml ]]")
      config = StringIO.new
      config.puts "# Installed by Onepush."
      config.puts "default_settings: &default_settings"
      config.puts "  secret_key_base: #{SecureRandom.hex(64)}"
      config.puts
      ["development", "staging", "production"].each do |env|
        config.puts "#{env}:"
        config.puts "  <<: *default_settings"
        config.puts
      end
      config.rewind
      sudo_upload(host, config, "#{app_dir}/shared/config/secrets.yml")
    end

    sudo(host, "cd #{app_dir}/shared/config && " +
      "chmod 600 database.yml secrets.yml && " +
      "chown #{owner}: database.yml secrets.yml")
  end
end

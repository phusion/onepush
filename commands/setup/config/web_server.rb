task :install_web_server => [:install_essentials, :install_passenger] do
  if MANIFEST['install_web_server']
    log_notice "Installing web server..."
    case MANIFEST['web_server_type']
    when 'nginx'
      install_nginx
      enable_passenger_nginx
      install_pomodori_nginx_vhosts
      install_nginx_service
    when 'apache'
      install_apache
    else
      abort "Unsupported web server. #{POMODORI_APP_NAME} supports 'nginx' and 'apache'."
    end
  end
end


def install_nginx
  on roles(:app) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      if nginx_installed?(host)
        ensure_nginx_has_passenger_support(host)
      else
        install_nginx_from_source_with_passenger(host)
      end
    when :debian
      if nginx_installed?(host)
        ensure_nginx_has_passenger_support(host)
      else
        if should_install_nginx_from_phusion_apt?
          install_nginx_from_phusion_apt(host)
        else
          install_nginx_from_source_with_passenger(host)
        end
      end
    else
      raise "Bug"
    end
    clear_cache(host, :nginx)
  end
end

def nginx_installed?(host)
  !!autodetect_nginx(host)
end

def ensure_nginx_has_passenger_support(host)
  # TODO
end

def should_install_nginx_from_phusion_apt?
  test("[[ -e /etc/apt/sources.list.d/passenger.list ]]")
end

def install_nginx_from_phusion_apt(host)
  if test("test -e /usr/bin/nginx && ! /usr/bin/nginx -V | grep -q passenger")
    # Remove upstream Nginx package, which does not include Phusion Passenger.
    sudo(host, "apt-get remove -y nginx nginx-core nginx-light nginx-full nginx-extras nginx-naxsi")
  end
  apt_get_install(host, %w(nginx-extras))

  sudo(host, "touch /var/run/pomodori/restart_web_server")
end

def install_nginx_from_source_with_passenger(host)
  installer = autodetect_passenger!(host)[:nginx_installer]
  _install_passenger_source_dependencies(host)
  sudo(host, "#{installer} --auto --auto-download --prefix=/opt/nginx --languages=")
end

def enable_passenger_nginx
  if MANIFEST['install_passenger']
    on roles(:app) do |host|
      config_file      = autodetect_nginx!(host)[:config_file]
      passenger_info   = autodetect_passenger!(host)
      ruby             = passenger_info[:ruby]
      passenger_config = passenger_info[:config_command]

      sudo(host, "sed -i 's|# passenger_root|passenger_root|' #{config_file}")
      sudo(host, "sed -i 's|# passenger_ruby|passenger_ruby|' #{config_file}")

      if !sudo_test(host, "grep -q passenger_root #{config_file}")
        passenger_root = capture("#{passenger_config} --root").strip

        io = StringIO.new
        sudo_download(host, config_file, io)

        config = io.string
        modified = config.sub!(/^http {/,
          "http {\n" +
          "    passenger_root #{passenger_root};\n" +
          "    passenger_ruby #{ruby};\n")

        if modified
          io = StringIO.new
          io.puts(config)
          io.rewind
          sudo_upload(host, io, config_file)
          sudo(host, "touch /var/run/pomodori/restart_web_server")
        else
          fatal_and_abort "Unable to modify the Nginx configuration file to enable Phusion Passenger. " +
            "Please do it manually: add the `passenger_root` and `passenger_ruby` directives to " +
            "#{config_file}, inside the `http` block."
        end
      end
    end
  end
end

def install_pomodori_nginx_vhosts
  if MANIFEST['install_web_server']
    on roles(:app) do |host|
      config_file = autodetect_nginx!(host)[:config_file]
      include_directive = "include /etc/pomodori/apps/*/shared/config/nginx-vhost.conf;"

      io = StringIO.new
      sudo_download(host, config_file, io)

      config = io.string
      if !config.include?(include_directive)
        modified = config.sub!(/^http {/,
          "http {\n" +
          "    #{include_directive}\n")
      end
      if modified
        io = StringIO.new
          io.puts(config)
          io.rewind
          sudo_upload(host, io, config_file)
          sudo(host, "touch /var/run/pomodori/restart_web_server")
      end
    end
  end
end

def install_nginx_service
  on roles(:app) do |host|
    nginx_info  = autodetect_nginx!(host)
    nginx_bin   = nginx_info[:binary]
    config_file = nginx_info[:config_file]

    if !nginx_info[:installed_from_system_package]
      case host.properties.fetch(:os_class)
      when :redhat
        yum_install(host, %w(runit))
      when :debian
        apt_get_install(host, %w(runit))
      else
        raise "Bug"
      end

      if !sudo_test(host, "grep -q '^daemon ' #{config_file}")
        log_info "Disabling daemon mode in #{config_file}."
        io = StringIO.new
        sudo_download(host, config_file, io)

        config = StringIO.new
        config.puts "daemon off;"
        config.puts(io.string)
        config.rewind

        sudo_upload(host, config, "/opt/nginx/conf/nginx.conf")
      elsif sudo_test(host, "grep '^daemon on;' /opt/nginx/conf/nginx.conf")
        log_info "Disabling daemon mode in /opt/nginx/conf/nginx.conf."
        io = StringIO.new
        sudo_download(host, "/opt/nginx/conf/nginx.conf", io)

        config = StringIO.new
        config.puts(io.string.sub(/^daemon on;/, 'daemon off;'))
        config.rewind

        sudo_upload(host, config, "/opt/nginx/conf/nginx.conf")
      end

      if !test("[[ -e /etc/service/nginx/run ]]")
        log_info "Installing Nginx Runit service."
        script = StringIO.new
        script.puts "#!/bin/bash"
        script.puts "# Installed by #{POMODORI_APP_NAME}."
        script.puts "set -e"
        script.puts "exec #{nginx_bin}"
        script.rewind

        sudo(host, "mkdir -p /etc/service/nginx")
        sudo_upload(host, script, "/etc/service/nginx/run.new")
        sudo(host, "chmod +x /etc/service/nginx/run.new && mv /etc/service/nginx/run.new /etc/service/nginx/run")
        # Wait for Runit to pick up this new service.
        sleep 1
      end
    end
  end
end


def install_apache
  on roles(:app) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      yum_install(host, %w(httpd))
    when :debian
      apt_get_install(host, %w(apache2))
    else
      raise "Bug"
    end
  end

  if MANIFEST['install_passenger']
    install_passenger_apache_module
  end
end

def install_passenger_apache_module
  on roles(:app) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      install_passenger_apache_module_from_source(host)
    when :debian
      if should_install_passenger_apache_module_from_apt?
        install_passenger_apache_module_from_apt(host)
      else
        install_passenger_apache_module_from_source(host)
      end
    else
      raise "Bug"
    end
  end
end

def should_install_passenger_apache_module_from_apt?
  test("[[ -e /etc/apt/sources.list.d/passenger.list ]]")
end

def install_passenger_apache_module_from_apt(host)
  apt_get_install(host, %w(libapache2-mod-passenger))
  if !test("[[ -e /etc/apache2/mods-enabled/passenger.load ]]")
    sudo(host, "a2enmod passenger && touch /var/run/pomodori/restart_web_server")
  end
end

def install_passenger_apache_module_from_source(host)
  _install_passenger_source_dependencies(host)
  passenger_info   = autodetect_passenger!(host)
  passenger_config = passenger_info[:config_command]
  installer        = passenger_info[:apache2_installer]

  # Locate location of the Apache module.
  capture("#{installer} --snippet") =~ /LoadModule passenger_module (.*)/
  module_path = $1

  # Check whether the Apache module is already installed.
  if !test("test -e #{module_path}")
    # Install dependencies.
    case host.properties.fetch(:os_class)
    when :redhat
      yum_install(host, %w(httpd-devel))
    when :debian
      apt_get_install(host, %w(apache2-dev))
    else
      raise "Bug"
    end

    # Install Apache module.
    sudo(host, "#{installer} --auto  --languages=")
    if host.properties.fetch(:os_class) == :redhat
      # Set proper SELinux permissions.
      passenger_root = capture("#{passenger_config} --root").strip
      if test("[[ -d #{passenger_root} ]]")
        sudo(host, "chcon -R -h -t httpd_sys_content_t #{passenger_root}")
      end
    end

    # Install config snippet.
    sudo(host, "#{installer} --snippet > /etc/apache2/mods-available/passenger.load")
    sudo(host, "echo > /etc/apache2/mods-available/passenger.conf")
    sudo(host, "a2enmod passenger && touch /var/run/pomodori/restart_web_server")
  end
end

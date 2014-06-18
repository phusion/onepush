task :install_web_server => [:install_essentials, :install_passenger] do
  if CONFIG['install_web_server']
    case CONFIG['web_server_type']
    when 'nginx'
      install_nginx
      enable_passenger_nginx
      install_nginx_service
    when 'apache'
      install_apache
    else
      abort "Unsupported web server. Flippo supports 'nginx' and 'apache'."
    end
  end
end


def install_nginx
  on roles(:app) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      raise "TODO"
    when :debian
      if !nginx_installed?
        if should_install_nginx_from_phusion_apt?
          install_nginx_from_phusion_apt(host)
        else
          install_nginx_from_source_with_passenger(host)
        end
      end
    else
      raise "Bug"
    end
  end
end

def nginx_installed?
  if test(b "[[ -e /usr/bin/nginx || -e /usr/local/bin/nginx ]]")
    true
  else
    files = capture("ls -1 /opt/*/*/nginx 2>/dev/null", :raise_on_non_zero_exit => false).split("\n")
    files.any?
  end
end

def should_install_nginx_from_phusion_apt?
  test("[[ -e /etc/apt/sources.list.d/passenger.list ]]")
end

def install_nginx_from_phusion_apt(host)
  case host.properties.fetch(:os_class)
  when :redhat
    raise "TODO"
  when :debian
    if test("test -e /usr/bin/nginx && ! /usr/bin/nginx -V | grep -q passenger")
      # Remove upstream Nginx package, which does not include Phusion Passenger.
      execute "apt-get remove -y nginx nginx-core nginx-light nginx-full nginx-extras nginx-naxsi"
    end
    apt_get_install(host, %w(nginx-extras))
  else
    raise "Bug"
  end

  execute "touch /var/run/flippo/restart_web_server"
end

def install_nginx_from_source_with_passenger(host)
  installer = autodetect_passenger![:nginx_installer]
  execute "#{installer} --auto --auto-download --prefix=/opt/nginx"
end

def enable_passenger_nginx
  if CONFIG['install_passenger']
    on roles(:app) do
      config_file      = autodetect_nginx![:config_file]
      passenger_info   = autodetect_passenger!
      ruby             = passenger_info[:ruby]
      passenger_config = passenger_info[:config_command]

      execute "sed -i 's|# passenger_root|passenger_root|' #{config_file}"
      execute "sed -i 's|# passenger_ruby|passenger_ruby|' #{config_file}"

      if !test("grep -q passenger_root #{config_file}")
        passenger_root = capture("#{passenger_config} --root").strip

        io = StringIO.new
        download!(config_file, io)

        config = io.string
        modified = config.sub!(/^http {/,
            "http {\n" +
            "    passenger_root #{passenger_root};\n" +
            "    passenger_ruby #{ruby};\n")

        if modified
          io = StringIO.new
          io.puts(config)
          io.rewind
          upload!(io, config_file)
          execute "touch /var/run/flippo/restart_web_server"
        else
          fatal_and_abort "Unable to modify the Nginx configuration file to enable Phusion Passenger. " +
            "Please do it manually: add the `passenger_root` and `passenger_ruby` directives to " +
            "#{config_file}, inside the `http` block."
        end
      end
    end
  end
end

def install_nginx_service
  on roles(:app) do
    nginx_info  = autodetect_nginx!
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

      if !test("grep -q '^daemon ' #{config_file}")
        info "Disabling daemon mode in #{config_file}"
        io = StringIO.new
        download!(config_file, io)

        config = StringIO.new
        config.puts "daemon off;"
        config.puts(io.string)
        config.rewind

        upload!(config, "/opt/nginx/conf/nginx.conf")
      elsif test("grep '^daemon on;' /opt/nginx/conf/nginx.conf")
        info "Disabling daemon mode in /opt/nginx/conf/nginx.conf"
        io = StringIO.new
        download!("/opt/nginx/conf/nginx.conf", io)

        config = StringIO.new
        config.puts(io.string.sub(/^daemon on;/, 'daemon off;'))
        config.rewind

        upload!(config, "/opt/nginx/conf/nginx.conf")
      end

      if !test("[[ -e /etc/service/nginx/run ]]")
        info "Installing Nginx Runit service"
        script = StringIO.new
        script.puts "#!/bin/bash"
        script.puts "# Installed by Flippo."
        script.puts "set -e"
        script.puts "exec #{nginx_bin}"
        script.rewind

        execute "mkdir -p /etc/service/nginx"
        upload!(script, "/etc/service/nginx/run.new")
        execute "chmod +x /etc/service/nginx/run.new && mv /etc/service/nginx/run.new /etc/service/nginx/run"
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
      raise "TODO"
    when :debian
      apt_get_install(host, %w(apache2))
    else
      raise "Bug"
    end
  end

  if CONFIG['install_passenger']
    install_passenger_apache_module
  end
end

def install_passenger_apache_module
  on roles(:app) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      raise "TODO"
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
    execute "a2enmod passenger && touch /var/run/flippo/restart_web_server"
  end
end

def install_passenger_apache_module_from_source(host)
  ruby = autodetect_ruby_interpreter_for_passenger!

  # Locate location of the Apache module.
  installer = "#{ruby} /opt/passenger/current/bin/passenger-install-apache2-module"
  capture("#{installer} --snippet") =~ /LoadModule passenger_module (.*)/
  module_path = $1

  # Check whether the Apache module is already installed.
  if !test("test -e #{module_path}")
    # Install dependencies.
    case host.properties.fetch(:os_class)
    when :redhat
      raise "TODO"
    when :debian
      apt_get_install(host, %w(apache2-dev))
    else
      raise "Bug"
    end

    # Install Apache module.
    execute "#{installer} --auto"
    # Install config snippet.
    execute "#{installer} --snippet > /etc/apache2/mods-available/passenger.load"
    execute "echo > /etc/apache2/mods-available/passenger.conf"
    execute "a2enmod passenger && touch /var/run/flippo/restart_web_server"
  end
end

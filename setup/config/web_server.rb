task :install_web_server => [:install_essentials, :install_passenger] do
  if CONFIG['install_web_server']
    case CONFIG['web_server_type']
    when 'nginx'
      install_nginx
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

    execute "sed -i 's|# passenger_root|passenger_root|' /etc/nginx/nginx.conf"
    execute "sed -i 's|# passenger_ruby|passenger_ruby|' /etc/nginx/nginx.conf"
    if !test("grep -q passenger_root /etc/nginx/nginx.conf")
      passenger_root = capture("/usr/bin/passenger-config --root").strip
      config = StringIO.new
      config.puts "passenger_root #{passenger_root};"
      config.puts "passenger_ruby #{find_ruby_interpreter_for_passenger};"
      config.rewind
      upload!("/etc/nginx/conf.d/passenger.conf", config)
    end
  else
    raise "Bug"
  end

  execute "touch /var/run/flippo/restart_web_server"
end

def install_nginx_from_source_with_passenger(host)
  ruby = find_ruby_interpreter_for_passenger
  if test("[[ -e /usr/bin/passenger-install-nginx-module ]]")
    installer = "/usr/bin/passenger-install-nginx-module"
  else
    installer = "#{ruby} /opt/passenger/current/bin/passenger-install-nginx-module"
  end
  execute "#{installer} --auto --auto-download --prefix=/opt/nginx"
end

def install_nginx_service
  on roles(:app) do
    if test("[[ ! -e /usr/bin/nginx && -e /opt/nginx/sbin/nginx ]]")
      case host.properties.fetch(:os_class)
      when :redhat
        yum_install(host, %w(runit))
      when :debian
        apt_get_install(host, %w(runit))
      else
        raise "Bug"
      end

      if !test("grep -q '^daemon ' /opt/nginx/conf/nginx.conf")
        info "Disabling daemon mode in /opt/nginx/conf/nginx.conf"
        config = StringIO.new
        download!("/opt/nginx/conf/nginx.conf", config)

        new_config = StringIO.new
        new_config.puts "daemon off;"
        new_config.puts(config.string)
        new_config.rewind

        upload!(new_config, "/opt/nginx/conf/nginx.conf")
      elsif test("grep '^daemon on;' /opt/nginx/conf/nginx.conf")
        info "Disabling daemon mode in /opt/nginx/conf/nginx.conf"
        config = StringIO.new
        download!("/opt/nginx/conf/nginx.conf", config)

        new_config = StringIO.new
        new_config.puts(config.string.sub(/^daemon on;/, 'daemon off;'))
        new_config.rewind

        upload!(new_config, "/opt/nginx/conf/nginx.conf")
      end

      if !test("[[ -e /etc/service/nginx/run ]]")
        info "Installing Nginx Runit service"
        script = StringIO.new
        script.puts "#!/bin/bash"
        script.puts "# Installed by Flippo."
        script.puts "set -e"
        script.puts "exec /opt/nginx/sbin/nginx"
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
  ruby = find_ruby_interpreter_for_passenger

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


# Determine Ruby interpreter to use for running the Phusion Passenger installer.
def find_ruby_interpreter_for_passenger
  if test("[[ -e /usr/bin/ruby ]]")
    "/usr/bin/ruby"
  elsif test("[[ -e /usr/local/rvm/wrappers/default/ruby ]]")
    "/usr/local/rvm/wrappers/default/ruby"
  else
    abort "Unable to find a Ruby interpreter on the system. This is probably " +
      "a bug in Flippo. Please report this to the authors."
  end
end

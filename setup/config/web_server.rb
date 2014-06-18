task :install_web_server => :install_passenger do
  if CONFIG['install_web_server']
    case CONFIG['web_server_type']
    when 'nginx'
      install_nginx
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
      raise "TODO"
    else
      raise "Bug"
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
      if test("[[ -e /etc/apt/sources.list.d/passenger.list ]]")
        apt_get_install(host, %w(libapache2-mod-passenger))
        if !test("[[ -e /etc/apache2/mods-enabled/passenger.load ]]")
          execute "a2enmod passenger && touch /var/run/flippo/restart_web_server"
        end
      else
        # Determine Ruby interpreter to use for running the installer.
        if test("[[ -e /usr/bin/ruby ]]")
          ruby = "/usr/bin/ruby"
        elsif test("[[ -e /usr/local/rvm/wrappers/default/ruby ]]")
          ruby = "/usr/local/rvm/wrappers/default/ruby"
        else
          abort "Unable to find a Ruby interpreter on the system. This is probably " +
            "a bug in Flippo. Please report this to the authors."
        end

        # Locate location of the Apache module.
        installer = "#{ruby} /opt/passenger/current/bin/passenger-install-apache2-module"
        capture("#{installer} --snippet") =~ /LoadModule passenger_module (.*)/
        module_path = $1

        # Check whether everything is installed correctly.
        if !test("test -e #{module_path}")
          # Install dependencies.
          apt_get_install(host, %w(apache2-dev libcurl4-openssl-dev))
          # Install Apache module.
          execute "#{installer} --auto"
          # Install config snippet.
          execute "#{installer} --snippet > /etc/apache2/mods-available/passenger.load"
          execute "echo > /etc/apache2/mods-available/passenger.conf"
          execute "a2enmod passenger && touch /var/run/flippo/restart_web_server"
        end
      end
    else
      raise "Bug"
    end
  end
end

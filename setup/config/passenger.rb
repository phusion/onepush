task :install_passenger => :install_essentials do
  if CONFIG['install_passenger']
    on roles(:app) do |host|
      if !test("[[ -e /usr/bin/passenger-config || -e /opt/passenger/current/bin/passenger-config ]]")
        case host.properties.fetch(:os_class)
        when :redhat
          install_passenger_from_source(host)
        when :debian
          codename = capture(b "lsb_release -c | awk '{ print $2 }'").strip
          if !CONFIG['passenger_force_install_from_source'] && passenger_apt_repo_available?(codename)
            install_passenger_from_apt(host, codename)
          else
            install_passenger_from_source(host)
          end
        else
          raise "Bug"
        end
      end
    end
  end
end

def passenger_apt_repo_available?(codename)
  http = Net::HTTP.new("oss-binaries.phusionpassenger.com", 443)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER
  response = http.request(Net::HTTP::Head.new("/apt/passenger/dists/#{codename}/Release"))
  response.code == "200"
end

def install_passenger_from_apt(host, codename)
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

  if CONFIG['passenger_enterprise']
    apt_get_install(host, "passenger-enterprise")
  else
    apt_get_install(host, "passenger")
  end

  # if CONFIG['install_web_server']
  #   case CONFIG['web_server_type']
  #   when 'nginx'
  #     apt_get_install(host, %w(nginx-extras passenger))
  #     md5 = capture("md5sum /etc/nginx/nginx.conf")
  #     execute "sed -i 's|# passenger_root|passenger_root|' /etc/nginx/nginx.conf"
  #     execute "sed -i 's|# passenger_ruby|passenger_ruby|' /etc/nginx/nginx.conf"

  #     # Restart Nginx if config changed.
  #     if capture("md5sum /etc/nginx/nginx.conf") != md5
  #       execute "service nginx restart"
  #     end
  #   when 'apache'
  #     apt_get_install(host, "libapache2-mod-passenger")
  #     if !test("[[ -e /etc/apache2/mods-enabled/passenger.load ]]")
  #       execute "a2enmod passenger && service apache2 restart"
  #     end
  #   else
  #     abort "Unsupported web server. Flippo supports 'nginx' and 'apache'."
  #   end
  # end
end

def install_passenger_from_source(host)
  # Install a Ruby runtime for Passenger.
  if CONFIG['type'] == 'ruby'
    invoke :install_ruby_runtime
  else
    # If the app language is not Ruby, we don't want to install a full-blown
    # Ruby runtime for apps. We just want to install a minimalist Ruby just to
    # be able to run Passenger.
    case host.properties.fetch(:os_class)
    when :redhat
      execute "yum install -y ruby rubygem-rake"
    when :debian
      apt_get_install(host, %w(ruby ruby-dev rake))
    end
  end

  # Install Passenger.
  if !test("[[ -e /opt/passenger/current ]]")
    tmpdir = capture("mktemp -d /tmp/flippo.XXXXXX").strip
    begin
      # Download tarball and infer directory name.
      passenger_tarball_url = "https://www.phusionpassenger.com/latest_stable_tarball"
      execute("curl --fail --silent -L -o #{tmpdir}/passenger.tar.gz #{passenger_tarball_url}")
      dirname = capture("tar tzf #{tmpdir}/passenger.tar.gz | head -n 1").strip.sub(/\/$/, '')

      # Extract tarball.
      execute("mkdir -p /opt/passenger && " +
        "cd /opt/passenger && " +
        "tar xzf #{tmpdir}/passenger.tar.gz && " +
        "chown -R root: #{dirname}")

      # Update symlink.
      execute("rm -f /opt/passenger/current && " +
        "cd /opt/passenger && " +
        "ln -s #{dirname} current")
    ensure
      execute("rm -rf #{tmpdir}")
    end
  end
end

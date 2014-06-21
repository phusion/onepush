task :install_language_runtime => :install_essentials do
  notice "Installing language runtime..."
  case ABOUT['type']
  when 'ruby'
    invoke :install_ruby_runtime
    install_common_ruby_app_dependencies
  end
end

task :install_ruby_runtime => :install_essentials do
  on roles(:app) do |host|
    _install_ruby_runtime(host)
  end
end

def _install_ruby_runtime(host)
  case SETUP['ruby_manager']
  when 'rvm'
    install_rvm(host)
  end
  clear_cache(host, :ruby)
end

def install_rvm(host)
  if !test("[[ -e /usr/local/rvm/bin/rvm ]]")
    sudo(host, "curl -sSL https://get.rvm.io | bash -s stable --ruby")
  end
  if !test("[[ -h /usr/local/rvm/rubies/default ]]")
    rubies = capture("ls -1d /usr/local/rvm/rubies/ruby-* 2>/dev/null; true")
    rubies = rubies.split("\n").map { |x| File.basename(x) }.sort
    if rubies.empty?
      sudo(host, "/usr/local/rvm/bin/rvm install ruby")
    else
      sudo(host, "/bin/bash -lc 'rvm --default #{rubies.last}'")
    end
  end

  ruby_version = ABOUT['ruby_version']
  if ruby_version && !test("/usr/local/rvm/bin/rvm #{ruby_version} do ruby --version")
    sudo(host, "/usr/local/rvm/bin/rvm install #{ruby_version}")
  end
end

def install_common_ruby_app_dependencies
  if SETUP['install_common_ruby_app_dependencies']
    on roles(:app) do |host|
      case host.properties.fetch(:os_class)
      when :redhat
        packages = []
        # For Rails.
        packages.concat %w(nodejs)
        # For Nokogiri.
        packages.concat %w(libxml2-devel libxslt-devel)
        # For rmagick and minimagick
        packages.concat %w(ImageMagick ImageMagick-devel)
        # For mysql and mysql2.
        packages.concat %w(mysql-devel)
        # For sqlite3.
        packages.concat %w(sqlite-devel)
        # For postgres and pg.
        packages.concat %w(postgresql-devel)
        # For capybara-webkit.
        # TODO: check whether package name has changed in Red Hat 7
        packages.concat %w(qt-devel)
        # For curb.
        packages.concat %w(libcurl-devel)

        yum_install(host, packages)
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

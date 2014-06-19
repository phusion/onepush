task :install_language_runtime => :install_essentials do
  case CONFIG['type']
  when 'ruby'
    invoke :install_ruby_runtime
    install_common_ruby_app_dependencies
  end
end

task :install_ruby_runtime do
  case CONFIG['ruby_manager']
  when 'rvm'
    install_rvm
  end
end

def install_rvm
  on roles(:app) do |host|
    if !test("[[ -e /usr/local/rvm/bin/rvm ]]")
      sudo(host, "curl -sSL https://get.rvm.io | bash -s stable --ruby")
    end
    if !test("[[ -h /usr/local/rvm/rubies/default ]]")
      rubies = capture("ls -1 /usr/local/rvm/rubies/ruby-* 2>/dev/null; true")
      rubies = rubies.split("\n").map { |x| File.dirname(x) }.sort
      if rubies.empty?
        sudo(host, "/usr/local/rvm/bin/rvm install ruby")
      else
        sudo(host, "/usr/local/rvm/bin/rvm --default #{rubies.last}")
      end
    end
    clear_cache(:ruby)
  end
end

def install_common_ruby_app_dependencies
  if CONFIG['install_common_ruby_app_dependencies']
    on roles(:app) do |host|
      case host.properties.fetch(:os_class)
      when :redhat
        packages = []
        # For Rails.
        packages.concat %w(nodejs)
        # For Nokogiri.
        packages.concat %w(libxml2-devel libxslt-devel)

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

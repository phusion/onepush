task :install_language_runtime => :install_essentials do
  log_notice "Installing language runtime..."
  case MANIFEST['type']
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
  case MANIFEST['ruby_manager']
  when 'rvm'
    install_rvm(host)
  end
  clear_cache(host, :ruby)
end

def install_rvm(host)
  if !test("[[ -e /usr/local/rvm/bin/rvm ]]")
    sudo(host, "gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3")
    sudo(host, "curl -sSL https://get.rvm.io | bash -s 1.26.5 --ruby")
  end

  ruby_version = MANIFEST['ruby_version']
  if ruby_version && !test("/usr/local/rvm/bin/rvm #{ruby_version} do ruby --version")
    log_info "Installing Ruby interpreter: #{ruby_version}"
    sudo(host, "/usr/local/rvm/bin/rvm install #{ruby_version}")
  end

  if !test("[[ -h /usr/local/rvm/rubies/default ]]")
    rubies = capture("ls -1d /usr/local/rvm/rubies/ruby-* 2>/dev/null; true")
    rubies = rubies.split(/\r?\n/).map { |x| File.basename(x) }.sort
    if rubies.empty?
      log_info "Installing Ruby interpreter: latest version"
      sudo(host, "/usr/local/rvm/bin/rvm install ruby")
      rubies = capture("ls -1d /usr/local/rvm/rubies/ruby-* 2>/dev/null; true")
      rubies = rubies.split(/\r?\n/).map { |x| File.basename(x) }.sort
    end
    sudo(host, "/bin/bash -lc 'rvm --default #{rubies.last}'")
  end

  io = StringIO.new
  io.puts "# Installed by #{POMODORI_APP_NAME}."
  io.puts "# Relaxing sudo defaults for RVM: https://rvm.io/integration/sudo"
  io.puts 'Defaults env_keep += "rvm_bin_path GEM_HOME IRBRC MY_RUBY_HOME ' +
    'rvm_path rvm_prefix rvm_version GEM_PATH rvmsudo_secure_path RUBY_VERSION ' +
    'rvm_ruby_string rvm_delete_flag"'
  io.rewind
  sudo_upload(host, io, "/etc/sudoers.d/rvm", :chmod => "u=r,g=r,o=")

  io = StringIO.new
  io.puts "# Installed by #{POMODORI_APP_NAME}."
  if sudo_test(host, "shopt -s nullglob && grep -q secure_path /etc/sudoers /etc/sudoers.d/*")
    io.puts "export rvmsudo_secure_path=1"
  else
    io.puts "export rvmsudo_secure_path=0"
  end
  io.rewind
  sudo_upload(host, io, "/etc/profile.d/rvm-sudo.sh", :chmod => 755)
end

def install_common_ruby_app_dependencies
  if MANIFEST['install_common_ruby_app_dependencies']
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
        # For curb.
        packages.concat %w(libcurl4-openssl-dev)

        apt_get_install(host, packages)
      else
        raise "Bug"
      end
    end
  end
end

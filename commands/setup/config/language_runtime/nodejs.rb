task :install_nodejs_runtime => :install_essentials do
  on roles(:app) do |host|
    _install_nodejs_runtime(host)
  end
end

def _install_nodejs_runtime(host)
  case APP_CONFIG.nodejs_manager
  when 'nvm'
    install_or_upgrade_nvm(host)
  end
  clear_cache(host, :nodejs)
end

def install_or_upgrade_nvm(host)
  if !test_cond("-e /usr/local/nvm/nvm.sh")
    install_nvm(host)
  else
    nvm_version = capture(b "source /usr/local/nvm/nvm.sh && nvm --version").strip
    if nvm_version.to_s.empty?
      install_nvm(host)
    elsif compare_version(nvm_version, APP_CONFIG.nvm_min_version) < 0
      log_info "NVM #{nvm_version} is older than required version #{APP_CONFIG.nvm_min_version}. Upgrading it."
      upgrade_nvm(host)
    else
      log_info "NVM #{nvm_version} is recent enough."
    end
  end

  install_nvm_bash_profile(host)

  nodejs_version = APP_CONFIG.nodejs_version
  if nodejs_version
    if !sudo_test(host, "source /usr/local/nvm/nvm.sh && nvm ls #{nodejs_version}")
      install_nodejs_dependencies(host)
      sudo(host, "source /usr/local/nvm/nvm.sh && nvm install #{nodejs_version}")
    end
  elsif !sudo_test(host, "source /usr/local/nvm/nvm.sh && nvm list stable")
    install_nodejs_dependencies(host)
    sudo(host, "source /usr/local/nvm/nvm.sh && nvm install stable")
  end

  default = sudo_capture(host, "source /usr/local/nvm/nvm.sh && nvm alias default").strip
  if default.empty?
    if nodejs_version
      sudo(host, "source /usr/local/nvm/nvm.sh && nvm alias default #{nodejs_version}")
    else
      sudo(host, "source /usr/local/nvm/nvm.sh && nvm alias default stable")
    end
  end
end

def install_nvm(host)
  sudo(host, "curl -sSL https://raw.githubusercontent.com/creationix/nvm/v0.22.0/install.sh " +
    "| env NVM_DIR=/usr/local/nvm bash")
end

def upgrade_nvm(host)
  # The install also upgrades.
  install_nvm(host)
end

def install_nvm_bash_profile(host)
  if !test_cond("-e /etc/profile.d/nvm.sh")
    io = StringIO.new
    io.puts "# Installed by #{POMODORI_APP_NAME}."
    io.puts "NVM_DIR=/usr/local/nvm; export NVM_DIR"
    io.puts '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
    io.rewind
    sudo_upload(host, io, "/etc/profile.d/nvm.sh",
      :chmod => 755,
      :chown => "root:")
  end
end

def install_nodejs_dependencies(host)
  case host.properties.fetch(:os_class)
  when :redhat
    yum_install(host, ["openssl-devel"])
  when :debian
    apt_get_install(host, ["libssl-dev"])
  end
end

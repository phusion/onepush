def _check_resetup_necessary(host)
  id       = PARAMS.app_id
  app_dir  = APP_CONFIG.app_dir
  pomodori_repo_path   = "#{app_dir}/pomodori_repo"
  server_manifest_path = "#{app_dir}/pomodori-manifest.json"

  if !sudo_test(host, "[[ -e #{pomodori_repo_path} && -e /etc/pomodori/apps/#{id} && -e #{server_manifest_path} ]]")
    return true
  end

  server_manifest_str = sudo_download_to_string(host, server_manifest_path)
  begin
    server_manifest = JSON.parse(server_manifest_str)
  rescue JSON::ParserError
    log_warn("The manifest file on the server (#{server_manifest_path}) is " +
      "corrupted. Will re-setup server in order to fix things.")
    return true
  end

  Pomodori::AppConfig::CHANGEABLE_PROPERTIES.each do |name|
    if APP_CONFIG[name] != server_manifest[name]
      log_warn("The app config has changed. Will re-setup server.")
      return true
    end
  end
  Pomodori::Commands::SetupParams::RESETUP_PROPERTIES.each do |name|
    if PARAMS[name] != server_manifest[name]
      log_warn("The app config has changed. Will re-setup server.")
      return true
    end
  end

  if APP_CONFIG.type == 'ruby' && APP_CONFIG.ruby_manager == 'rvm'
    if !test_cond("-e /usr/local/rvm/bin/rvm")
      log_warn("RVM is not installed. Will re-setup server.")
      return true
    end

    rvm_version = capture("/usr/local/rvm/bin/rvm --version").strip.split(" ")[1]
    if rvm_version.to_s.empty?
      log_warn("RVM appears to be broken. Will re-setup server.")
      return true
    elsif compare_version(rvm_version, APP_CONFIG.rvm_min_version) < 0
      log_warn "RVM #{rvm_version} is older than required version #{APP_CONFIG.rvm_min_version}. Will re-setup server."
      return true
    end

    ruby_version = APP_CONFIG.ruby_version
    if !test("/usr/local/rvm/bin/rvm #{ruby_version} do ruby --version")
      log_warn("Ruby version #{ruby_version} not installed. Will re-setup server.")
      return true
    end
  end

  false
end

task :check_resetup_necessary => [:install_essentials, :check_setup_version_compatibility] do
  if PARAMS.if_needed
    mutex  = Mutex.new
    states = []

    log_notice "Checking whether server setup is up-to-date..."

    on roles(:app) do |host|
      should_resetup = _check_resetup_necessary(host)
      mutex.synchronize { states << should_resetup }
    end

    if states.all? { |should_resetup| !should_resetup }
      log_info "Server setup is up-to-date. Skipping full setup process."
      report_progress(TOTAL_STEPS, TOTAL_STEPS)
      exit
    end
  end
end

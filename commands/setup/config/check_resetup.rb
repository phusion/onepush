def _check_resetup_necessary(host)
  id       = PARAMS.app_id
  app_dir  = APP_CONFIG.app_dir
  pomodori_repo_path     = "#{app_dir}/pomodori_repo"
  server_app_config_path = "#{app_dir}/pomodori-app-config.json"

  if !sudo_test(host, "[[ -e #{pomodori_repo_path} && -e /etc/pomodori/apps/#{id} && -e #{server_app_config_path} ]]")
    return true
  end

  server_app_config_str = sudo_download_to_string(host, server_app_config_path)
  begin
    server_app_config = JSON.parse(server_app_config_str)
  rescue JSON::ParserError
    log_warn("The app config file on the server (#{server_app_config_path}) is " +
      "corrupted. Will re-setup server in order to fix things.")
    return true
  end

  Pomodori::AppConfig::CHANGEABLE_PROPERTIES.each do |name|
    if APP_CONFIG[name] != server_app_config[name]
      log_warn("The app config has changed. Will re-setup server.")
      return true
    end
  end

  if APP_CONFIG.type == 'ruby' && APP_CONFIG.ruby_manager == 'rvm'
    ruby_version = APP_CONFIG.ruby_version
    if !test("/usr/local/rvm/bin/rvm #{ruby_version} do ruby --version")
      log_warn("Ruby version #{ruby_version} not installed. Will re-setup server.")
      return true
    end
  end

  false
end

task :check_resetup_necessary => :install_essentials do
  if PARAMS.if_needed
    mutex  = Mutex.new
    states = []

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

def _check_server_setup(host)
  log_notice "Checking server setup..."
  report_progress(1, TOTAL_STEPS)

  if !check_server_setup_and_return_result(host, true)
    fatal_and_abort "The server must be re-setup. Please run 'pomodori setup'."
  end
end

def check_server_setup_and_return_result(host, last_chance)
  id = PARAMS.app_id
  set :application, id

  # Infer app dir
  begin
    app_dir = capture("readlink /etc/pomodori/apps/#{id}; true").strip
  rescue Net::SSH::AuthenticationFailed => e
    if last_chance
      raise e
    else
      # Probably means that the server isn't setup yet.
      return false
    end
  end
  if app_dir.empty?
    return false
  end
  set(:deploy_to, app_dir)
  set(:repo_url, "#{app_dir}/pomodori_repo")

  # Download previous setup manifest
  json = download_to_string("#{app_dir}/pomodori-app-config.json")
  server_app_config = JSON.parse(io.string)
  set(:pomodori_server_app_config, server_app_config)

  # Check whether the requested Ruby version is installed
  if APP_CONFIG.ruby_version
    set :rvm_ruby_version, APP_CONFIG.ruby_version
  end
  Rake::Task['rvm:hook'].reenable
  invoke 'rvm:hook'
  rvm_path = fetch(:rvm_path)
  ruby_version = fetch(:rvm_ruby_version)
  if !test("#{rvm_path}/bin/rvm #{ruby_version} do ruby --version")
    return false
  end

  # Check whether anything else has been changed, and thus requires
  # a new 'pomodori setup' call
  Pomodori::AppConfig::CHANGEABLE_PROPERTIES.each do |name|
    if APP_CONFIG[name] != server_app_config[name]
      return false
    end
  end

  true
end

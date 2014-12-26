require_relative '../../../setup/params'

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

  _check_setup_version_compatibility(host)

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
  server_manifest_str = download_to_string("#{app_dir}/pomodori-manifest.json")
  server_manifest = JSON.parse(server_manifest_str)
  set(:pomodori_server_manifest, server_manifest)

  if APP_CONFIG.ruby_manager == 'rvm'
    # Check whether RVM is up-to-date and whether the requested Ruby
    # version is installed
    if APP_CONFIG.ruby_version
      set :rvm_ruby_version, APP_CONFIG.ruby_version
    end
    Rake::Task['rvm:hook'].reenable
    invoke 'rvm:hook'
    rvm_path = fetch(:rvm_path)
    ruby_version = fetch(:rvm_ruby_version)
    rvm_version = capture("#{rvm_path}/bin/rvm --version").strip.split(" ")[1]
    if rvm_version.to_s.empty?
      return false
    elsif compare_version(rvm_version, APP_CONFIG.rvm_min_version) < 0
      return false
    elsif !test("#{rvm_path}/bin/rvm #{ruby_version} do ruby --version")
      return false
    end
  end

  # Check whether anything else has been changed, and thus requires
  # a new 'pomodori setup' call
  Pomodori::AppConfig::CHANGEABLE_PROPERTIES.each do |name|
    if APP_CONFIG[name] != server_manifest[name]
      return false
    end
  end
  Pomodori::Commands::SetupParams::RESETUP_PROPERTIES.each do |name|
    if PARAMS[name] != server_manifest[name]
      return false
    end
  end

  true
end

def database_empty?(host)
  result = false
  mktempdir(host, :sudo => false) do |tmpdir|
    upload!("#{ROOT}/commands/deploy/ruby/dbcheck.rb", "#{tmpdir}/dbcheck.rb")
    output = capture(:bundle, "exec", "ruby", "#{tmpdir}/dbcheck.rb")
    result = output =~ /database is empty/
  end
  result
end

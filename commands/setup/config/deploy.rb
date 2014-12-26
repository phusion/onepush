require 'thread'
require 'json'
require 'stringio'
require 'securerandom'
require 'shellwords'
require 'net/http'
require 'net/https'
require_relative '../../../lib/app_config'
require_relative '../../../lib/version'

TOTAL_STEPS = 16

# If Capistrano is terminated, having a PTY will allow
# all commands on the server to properly terminate.
set :pty, true


after :production, :initialize_pomodori do
  Pomodori::CapistranoSupport.initialize!
  on roles(:app, :db) do |host|
    log_notice "Setting up server: #{host}"
  end
end


task :run_postsetup => :install_essentials do
  log_notice "Running post-setup scripts..."
  on roles(:app, :db) do |host|
    APP_CONFIG.postsetup_script.each do |script|
      sudo(host, script, :pipefail => false)
    end
  end
end

task :update_pomodori_server_manifest => :install_essentials do
  log_notice "Saving manifest on the server..."
  id      = PARAMS.app_id
  app_dir = APP_CONFIG.app_dir
  config  = JSON.pretty_generate(generate_server_manifest(PARAMS, APP_CONFIG))

  on roles(:app) do |host|
    user = APP_CONFIG.user
    sudo_upload(host, config, "#{app_dir}/pomodori-manifest.json",
      :chown => "#{user}:",
      :chmod => "600")
    sudo(host, "mkdir -p /etc/pomodori/apps && " +
      "cd /etc/pomodori/apps && " +
      "rm -f #{id} && " +
      "ln -s #{app_dir} #{id}")
  end

  on roles(:app, :db) do |host|
    sudo(host, "mkdir -p /etc/pomodori/setup && " +
      "cd /etc/pomodori/setup && " +
      "date +%s > last_run_time && " +
      "echo #{Pomodori::VERSION_STRING} > last_run_version && " +
      "echo #{Pomodori::SETUP_VERSION} > last_run_setup_version && " +
      "echo '#{POMODORI_APP_NAME} #{Pomodori::VERSION_STRING}' > last_run_version_name")
  end
end

task :restart_services => :install_essentials do
  log_notice "Restarting services..."
  on roles(:app) do |host|
    if test("sudo test -e /var/run/pomodori/restart_web_server")
      sudo(host, "rm -f /var/run/pomodori/restart_web_server")
      case APP_CONFIG.web_server_type
      when 'nginx'
        nginx_info = autodetect_nginx!(host)
        sudo(host, nginx_info[:configtest_command])
        if nginx_info[:restart_command]
          sudo(host, nginx_info[:restart_command])
        end
      when 'apache'
        if test_cond("-e /etc/init.d/apache2")
          sudo(host, "/etc/init.d/apache2 restart")
        elsif test_cond("-e /etc/init.d/httpd")
          sudo(host, "/etc/init.d/httpd restart")
        end
      else
        abort "Unsupported web server. #{POMODORI_APP_NAME} supports 'nginx' and 'apache'."
      end
    end
  end
end

desc "Setup the server environment"
task :setup do
  report_progress(1, TOTAL_STEPS)
  invoke :autodetect_os
  report_progress(2, TOTAL_STEPS)

  invoke :install_essentials
  report_progress(3, TOTAL_STEPS)

  invoke :check_setup_version_compatibility
  invoke :check_resetup_necessary
  report_progress(4, TOTAL_STEPS)

  invoke :install_language_runtime
  report_progress(5, TOTAL_STEPS)

  invoke :install_passenger
  report_progress(6, TOTAL_STEPS)

  invoke :install_web_server
  report_progress(7, TOTAL_STEPS)

  invoke :create_app_user
  invoke :create_app_dir
  invoke :create_app_secrets
  report_progress(8, TOTAL_STEPS)

  invoke :install_dbms
  report_progress(9, TOTAL_STEPS)

  invoke :install_database_client_software
  report_progress(10, TOTAL_STEPS)

  invoke :setup_database
  invoke :create_app_database_config
  report_progress(11, TOTAL_STEPS)

  invoke :install_additional_services
  report_progress(12, TOTAL_STEPS)

  invoke :create_app_vhost
  report_progress(13, TOTAL_STEPS)

  invoke :run_postsetup
  report_progress(14, TOTAL_STEPS)

  invoke :update_pomodori_server_manifest
  report_progress(15, TOTAL_STEPS)
  invoke :restart_services
  report_progress(TOTAL_STEPS, TOTAL_STEPS)

  log_notice "Finished setting up server."
end

require 'thread'
require 'json'
require 'stringio'
require 'securerandom'
require 'shellwords'
require 'net/http'
require 'net/https'
require_relative '../../lib/config'
require_relative '../../lib/version'

fatal_and_abort "The APP_ROOT option must be set" if !ENV['APP_ROOT']
fatal_and_abort "Please set the MANIFEST_JSON environment variable" if !ENV['MANIFEST_JSON']

MANIFEST = JSON.parse(ENV['MANIFEST_JSON'])
check_manifest_requirements(MANIFEST)
Onepush.set_manifest_defaults(MANIFEST)

TOTAL_STEPS = 15

# If Capistrano is terminated, having a PTY will allow
# all commands on the server to properly terminate.
set :pty, true


after :production, :initialize_onepush do
  Dir.chdir(ENV['APP_ROOT'])
  initialize_onepush_capistrano
  on roles(:app, :db) do |host|
    log_notice "Setting up server: #{host}"
  end
end


def _check_resetup_necessary(host)
  id       = MANIFEST['id']
  app_dir  = MANIFEST['app_dir']
  onepush_repo_path    = "#{app_dir}/onepush_repo"
  server_manifest_path = "#{app_dir}/onepush-setup.json"

  if !sudo_test(host, "[[ -e #{onepush_repo_path} && -e /etc/onepush/apps/#{id} && -e #{server_manifest_path} ]]")
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

  Onepush::CHANGEABLE_PROPERTIES.each do |name|
    if MANIFEST[name] != server_manifest[name]
      log_warn("Onepush.json has changed. Will re-setup server.")
      return true
    end
  end

  if MANIFEST['type'] == 'ruby' && MANIFEST['ruby_manager'] == 'rvm'
    ruby_version = MANIFEST['ruby_version']
    if !test("/usr/local/rvm/bin/rvm #{ruby_version} do ruby --version")
      log_warn("Ruby version #{ruby_version} not installed. Will re-setup server.")
      return true
    end
  end

  false
end

task :check_resetup_necessary => :install_essentials do
  if ENV['IF_NEEDED']
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

task :run_postsetup => :install_essentials do
  log_notice "Running post-setup scripts..."
  on roles(:app, :db) do |host|
    MANIFEST['postsetup_script'].each do |script|
      sudo(host, script, :pipefail => false)
    end
  end
end

task :install_onepush_manifest => :install_essentials do
  log_notice "Saving setup information..."
  id      = MANIFEST['id']
  app_dir = MANIFEST['app_dir']

  config = StringIO.new
  config.puts JSON.dump(MANIFEST)
  config.rewind

  on roles(:app) do |host|
    user = MANIFEST['user']
    sudo_upload(host, config, "#{app_dir}/onepush-setup.json",
      :chown => "#{user}:",
      :chmod => "600")
    sudo(host, "mkdir -p /etc/onepush/apps && " +
      "cd /etc/onepush/apps && " +
      "rm -f #{id} && " +
      "ln -s #{app_dir} #{id}")
  end

  on roles(:app, :db) do |host|
    sudo(host, "mkdir -p /etc/onepush/setup && " +
      "cd /etc/onepush/setup && " +
      "date +%s > last_run_time && " +
      "echo #{Onepush::VERSION_STRING} > last_run_version")
  end
end

task :restart_services => :install_essentials do
  log_notice "Restarting services..."
  on roles(:app) do |host|
    if test("sudo test -e /var/run/onepush/restart_web_server")
      sudo(host, "rm -f /var/run/onepush/restart_web_server")
      case MANIFEST['web_server_type']
      when 'nginx'
        nginx_info = autodetect_nginx!(host)
        sudo(host, nginx_info[:configtest_command])
        if nginx_info[:restart_command]
          sudo(host, nginx_info[:restart_command])
        end
      when 'apache'
        if test("[[ -e /etc/init.d/apache2 ]]")
          sudo(host, "/etc/init.d/apache2 restart")
        elsif test("[[ -e /etc/init.d/httpd ]]")
          sudo(host, "/etc/init.d/httpd restart")
        end
      else
        abort "Unsupported web server. Onepush supports 'nginx' and 'apache'."
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
  report_progress(8, TOTAL_STEPS)

  invoke :install_dbms
  report_progress(9, TOTAL_STEPS)

  setup_database(MANIFEST['database_type'], MANIFEST['database_name'],
    MANIFEST['database_user'])
  create_app_database_config(MANIFEST['app_dir'], MANIFEST['user'],
    MANIFEST['database_type'], MANIFEST['database_name'],
    MANIFEST['database_user'])
  report_progress(10, TOTAL_STEPS)

  invoke :install_additional_services
  report_progress(11, TOTAL_STEPS)

  invoke :create_app_vhost
  report_progress(12, TOTAL_STEPS)

  invoke :run_postsetup
  report_progress(13, TOTAL_STEPS)

  invoke :install_onepush_manifest
  report_progress(14, TOTAL_STEPS)
  invoke :restart_services
  report_progress(TOTAL_STEPS, TOTAL_STEPS)

  log_notice "Finished setting up server."
end

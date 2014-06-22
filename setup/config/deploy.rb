require 'json'
require 'stringio'
require 'securerandom'
require 'shellwords'
require 'net/http'
require 'net/https'
require_relative '../../lib/config'
require_relative '../../lib/version'

fatal_and_abort "Please set the MANIFEST_JSON environment variable" if !ENV['MANIFEST_JSON']
fatal_and_abort "The PWD option must be set" if !ENV['PWD']

MANIFEST = JSON.parse(ENV['MANIFEST_JSON'])
check_manifest_requirements(MANIFEST)
Onepush.set_manifest_defaults(MANIFEST)

TOTAL_STEPS = 13

# If Capistrano is terminated, having a PTY will allow
# all commands on the server to properly terminate.
set :pty, true


after :production, :initialize_onepush do
  Dir.chdir(ENV['PWD'])
  initialize_onepush_capistrano
  on roles(:app, :db) do |host|
    notice "Setting up server: #{host}"
  end
end


task :install_onepush_manifest => :install_essentials do
  notice "Saving setup information..."
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
  notice "Restarting services..."
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

  invoke :install_language_runtime
  report_progress(4, TOTAL_STEPS)

  invoke :install_passenger
  report_progress(5, TOTAL_STEPS)

  invoke :install_web_server
  report_progress(6, TOTAL_STEPS)

  invoke :create_app_user
  invoke :create_app_dir
  report_progress(7, TOTAL_STEPS)

  invoke :install_dbms
  report_progress(8, TOTAL_STEPS)

  setup_database(MANIFEST['database_type'], MANIFEST['database_name'],
    MANIFEST['database_user'])
  create_app_database_config(MANIFEST['app_dir'], MANIFEST['user'],
    MANIFEST['database_type'], MANIFEST['database_name'],
    MANIFEST['database_user'])
  report_progress(9, TOTAL_STEPS)

  invoke :install_additional_services
  report_progress(10, TOTAL_STEPS)

  invoke :create_app_vhost
  report_progress(11, TOTAL_STEPS)

  invoke :install_onepush_manifest
  report_progress(12, TOTAL_STEPS)
  invoke :restart_services
  report_progress(13, TOTAL_STEPS)

  notice "Finished."
end

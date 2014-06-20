require 'json'
require 'stringio'
require 'securerandom'
require 'shellwords'
require 'net/http'
require 'net/https'
require_relative '../../lib/my_pretty_formatter'
require_relative '../../lib/config'
require_relative '../../lib/version'

fatal_and_abort "Please set the MANIFEST_JSON environment variable" if !ENV['MANIFEST_JSON']
fatal_and_abort "The PWD option must be set" if !ENV['PWD']
MANIFEST = JSON.parse(ENV['MANIFEST_JSON'])

check_manifest_requirements(MANIFEST)
Onepush.set_manifest_defaults(MANIFEST)
ABOUT = MANIFEST['about']
SETUP = MANIFEST['setup']

set :pty, false


after :production, :initialize_onepush do
  Dir.chdir(ENV['PWD'])
  if path = ENV['SSHKIT_OUTPUT']
    output = File.open(path, "a")
  else
    output = STDOUT
  end
  SSHKit.config.output = Onepush::MyPrettyFormatter.new(output)
end


task :install_onepush_manifest => :install_essentials do
  id      = ABOUT['id']
  app_dir = SETUP['app_dir']

  config = StringIO.new
  config.puts JSON.dump(MANIFEST)
  config.rewind

  on roles(:app) do |host|
    user = SETUP['user']
    sudo_upload(host, config, "#{app_dir}/onepush-setup.json")
    sudo(host, "chown #{user}: #{app_dir}/onepush-setup.json && " +
      "chmod 600 #{app_dir}/onepush-setup.json")
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
  on roles(:app) do |host|
    if test("sudo test -e /var/run/onepush/restart_web_server")
      sudo(host, "rm -f /var/run/onepush/restart_web_server")
      case SETUP['web_server_type']
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
  invoke :autodetect_os
  invoke :install_essentials
  invoke :install_language_runtime
  invoke :install_passenger
  invoke :install_web_server
  invoke :create_app_user
  invoke :create_app_dir
  invoke :install_dbms
  setup_database(SETUP['database_type'], SETUP['database_name'],
    SETUP['database_user'])
  create_app_database_config(SETUP['app_dir'], SETUP['user'],
    SETUP['database_type'], SETUP['database_name'],
    SETUP['database_user'])
  invoke :create_app_vhost
  invoke :install_onepush_manifest
  invoke :restart_services
end

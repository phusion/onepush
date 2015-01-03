require 'shellwords'
require 'tmpdir'
require 'stringio'

TOTAL_STEPS = 7

# If Capistrano is terminated, having a PTY will allow
# all commands on the server to properly terminate.
set :pty, true


namespace :deploy do
  task :initialize_pomodori do
    Pomodori::CapistranoSupport.initialize!
    log_notice "Preparing deployment process..."
  end

  # Check whether the server is setup correctly, and autodetect various
  # information. The server is the primary source of truth, not the config
  # file.
  task :check_server_setup do
    on roles(:app) do |host|
      _check_server_setup(host)
    end
  end
end

# We install check_server_setup here so that it runs before the NVM initializer.
Capistrano::DSL.stages.each do |stage|
  after stage, 'deploy:initialize_pomodori'
  after stage, 'deploy:check_server_setup'
end

# Disable Capistrano 3.3 metrics collection.
Rake::Task["metrics:collect"].clear_actions


case APP_CONFIG.nodejs_manager
when 'nvm'
  require 'capistrano/nvm'
end

require 'capistrano/npm'

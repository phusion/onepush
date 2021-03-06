require 'shellwords'
require 'tmpdir'
require 'stringio'

TOTAL_STEPS = 11

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

# We install check_server_setup here so that it runs before the RVM hook.
Capistrano::DSL.stages.each do |stage|
  after stage, 'deploy:initialize_pomodori'
  after stage, 'deploy:check_server_setup'
end

# Disable Capistrano 3.3 metrics collection.
Rake::Task["metrics:collect"].clear_actions


# Includes tasks from other gems included in your Gemfile
#
# For documentation on these, see for example:
#
#   https://github.com/capistrano/rvm
#   https://github.com/capistrano/rbenv
#   https://github.com/capistrano/chruby
#   https://github.com/capistrano/bundler
#   https://github.com/capistrano/rails

case APP_CONFIG.ruby_manager
when 'rvm'
  require 'capistrano/rvm'
when 'rbenv'
  require 'capistrano/rbenv'
when 'chruby'
  require 'capistrano/chruby'
end


require 'capistrano/bundler'
if PARAMS.rails
  require 'capistrano/rails/assets'
  require 'capistrano/rails/migrations'
end

require_relative '../../lib/config'
require 'shellwords'
require 'tmpdir'
require 'stringio'
require 'json'

fatal_and_abort "Please set the APP_ROOT environment variable" if !ENV['APP_ROOT']
fatal_and_abort "Please set the MANIFEST_JSON environment variable" if !ENV['MANIFEST_JSON']

MANIFEST = JSON.parse(ENV['MANIFEST_JSON'])
check_manifest_requirements(MANIFEST)
Onepush.set_manifest_defaults(MANIFEST)

TOTAL_STEPS = 9.0

# If Capistrano is terminated, having a PTY will allow
# all commands on the server to properly terminate.
set :pty, true


namespace :deploy do
  task :initialize_onepush do
    Dir.chdir(ENV['APP_ROOT'])
    initialize_onepush_capistrano
    notice "Initializing..."
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
  after stage, 'deploy:initialize_onepush'
  after stage, 'deploy:check_server_setup'
end


# Includes tasks from other gems included in your Gemfile
#
# For documentation on these, see for example:
#
#   https://github.com/capistrano/rvm
#   https://github.com/capistrano/rbenv
#   https://github.com/capistrano/chruby
#   https://github.com/capistrano/bundler
#   https://github.com/capistrano/rails

case MANIFEST['ruby_manager']
when 'rvm'
  require 'capistrano/rvm'
when 'rbenv'
  require 'capistrano/rbenv'
when 'chruby'
  require 'capistrano/chruby'
end

require 'capistrano/bundler'
require 'capistrano/rails/assets'
require 'capistrano/rails/migrations'

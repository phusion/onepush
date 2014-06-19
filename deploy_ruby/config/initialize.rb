require_relative '../../lib/config'
require 'shellwords'
require 'tmpdir'

fatal_and_abort "Please set the APP_ROOT environment variable" if !ENV['APP_ROOT']
fatal_and_abort "Please set the CONFIG_FILE environment variable" if !ENV['CONFIG_FILE']

CONFIG = JSON.parse(File.read(ENV['CONFIG_FILE']))
check_config_requirements(CONFIG)
Flippo.set_config_defaults(CONFIG)

namespace :deploy do
  task :check_server_setup => 'rvm:hook' do
    on roles(:app) do
      name = CONFIG['name']
      if !test("[[ -h /etc/flippo/apps/#{name} ]]")
        fatal_and_abort "The server has not been setup for your app yet. Please run 'flippo setup'."
      end

      rvm_path = fetch(:rvm_path)
      ruby_version = fetch(:rvm_ruby_version)
      if !test("#{rvm_path}/bin/rvm #{ruby_version} do ruby --version")
        fatal_and_abort "Your app requires #{ruby_version}, but it isn't installed yet. Please run 'flippo setup'."
      end
    end
  end
end

# Always run server check, but run it before rvm:check.
Capistrano::DSL.stages.each do |stage|
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

case CONFIG['ruby_manager']
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

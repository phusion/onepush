require_relative '../../lib/config'

fatal_and_abort "Please set the CONFIG_FILE environment variable" if !ENV['CONFIG_FILE']
CONFIG = JSON.parse(File.read(ENV['CONFIG_FILE']))
check_config_requirements(CONFIG)
Flippo.set_config_defaults(CONFIG)

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

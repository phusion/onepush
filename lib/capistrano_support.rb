require 'json'
require_relative './capistrano_support/initialization'
require_relative './capistrano_support/logging'
require_relative './capistrano_support/caching'
require_relative './capistrano_support/commands'
require_relative './capistrano_support/file_manipulation'
require_relative './capistrano_support/package_management'
require_relative './capistrano_support/web_server_and_passenger'
require_relative './capistrano_support/misc'

STDOUT.sync = true
STDERR.sync = true

ROOT        = File.absolute_path(File.dirname(__FILE__) + "/..")
PARAMS_TEXT = ENV['POMODORI_PARAMS'] || abort("POMODORI_PARAMS must be set.")
PARAMS      = POMODORI_PARAMS_CLASS.new(JSON.parse(PARAMS_TEXT))
APP_CONFIG  = PARAMS.fetch(:app_config, nil)
POMODORI_APP_NAME = PARAMS.fetch(:pomodori_app_name, "Pomodori")

if PARAMS.respond_to?(:validate_and_finalize!)
  PARAMS.validate_and_finalize!
end

include Pomodori::CapistranoSupport::Logging
include Pomodori::CapistranoSupport::Caching
include Pomodori::CapistranoSupport::Commands
include Pomodori::CapistranoSupport::FileManipulation
include Pomodori::CapistranoSupport::PackageManagement
include Pomodori::CapistranoSupport::WebServerAndPassenger
include Pomodori::CapistranoSupport::Misc

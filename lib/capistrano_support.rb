require 'json'
require 'hashie'
require_relative './capistrano_support/initialization'
require_relative './capistrano_support/manifest'
require_relative './capistrano_support/logging'
require_relative './capistrano_support/commands'

ROOT        = File.absolute_path(File.dirname(__FILE__) + "/..")
CONFIG_TEXT = ENV['POMODORI_CONFIG'] || abort("POMODORI_CONFIG must be set.")
CONFIG      = Hashie::Mash.new(JSON.parse(CONFIG_TEXT))
MANIFEST    = CONFIG['manifest'] || {}

POMODORI_APP_NAME = CONFIG.pomodori_app_name || "Pomodori"

CONFIG.progress_base ||= 0
CONFIG.progress_ceil ||= 1
$current_progress = 0

include Pomodori::CapistranoSupport::Manifest
include Pomodori::CapistranoSupport::Logging
include Pomodori::CapistranoSupport::Commands

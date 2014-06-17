require_relative 'version'

module Flippo
  def self.set_config_defaults(config)
    # TODO
    config['flippo_setup_version'] = VERSION_STRING
  end
end

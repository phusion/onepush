require_relative 'version'

module Flippo
  def self.set_config_defaults(config)
    config['user'] ||= config['name']
    config['app_dir'] ||= "/var/www/#{config['name']}"

    config['database_type'] ||= 'postgresql'
    config['database_name'] ||= config['name']
    config['database_user'] = config['user']

    config['install_web_server'] = config.fetch('install_web_server', true)
    config['install_common_ruby_app_dependencies'] = config.fetch('install_common_ruby_app_dependencies', true)

    config['ruby_manager'] ||= 'rvm'
    config['web_server_type'] ||= 'nginx'

    config['passenger_enterprise'] = config.fetch('passenger_enterprise', false)

    config['flippo_version'] = VERSION_STRING
    config['flippo_config_format_version'] = CONFIG_FORMAT_VERSION_STRING
  end
end

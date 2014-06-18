require_relative 'version'

module Flippo
  class << self
    def set_config_defaults(config)
      config['user'] ||= config['name']
      config['app_dir'] ||= "/var/www/#{config['name']}"

      config['database_type'] ||= 'postgresql'
      config['database_name'] ||= config['name']
      config['database_user'] = config['user']

      set_boolean_default(config, 'install_passenger', true)
      set_boolean_default(config, 'install_web_server', true)
      set_boolean_default(config, 'install_common_ruby_app_dependencies', true)

      config['ruby_manager'] ||= 'rvm'
      config['web_server_type'] ||= 'nginx'

      set_boolean_default(config, 'passenger_enterprise', false)
      set_boolean_default(config, 'passenger_force_install_from_source', false)

      config['flippo_version'] = VERSION_STRING
      config['flippo_config_format_version'] = CONFIG_FORMAT_VERSION_STRING
    end

  private
    def set_boolean_default(config, name, default)
      if !config.has_key?(name)
        config[name] = default
      end
    end
  end
end

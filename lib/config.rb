require_relative 'version'

module Onepush
  class << self
    def set_manifest_defaults(manifest)
      about = (manifest['about'] ||= {})
      setup = (manifest['setup'] ||= {})

      setup['user'] ||= about['id']
      setup['app_dir'] ||= "/var/www/#{about['id']}"

      setup['database_type'] ||= 'postgresql'
      setup['database_name'] ||= about['id']
      setup['database_user'] = setup['user']

      set_boolean_default(setup, 'install_passenger', true)
      set_boolean_default(setup, 'install_web_server', true)
      set_boolean_default(setup, 'install_common_ruby_app_dependencies', true)

      setup['ruby_manager'] ||= 'rvm'
      setup['web_server_type'] ||= 'nginx'

      set_boolean_default(setup, 'passenger_enterprise', false)
      set_boolean_default(setup, 'passenger_force_install_from_source', false)

      setup['onepush_version'] = VERSION_STRING
      setup['onepush_manifest_format_version'] = MANIFEST_FORMAT_VERSION_STRING
    end

  private
    def set_boolean_default(config, name, default)
      if !config.has_key?(name)
        config[name] = default
      end
    end
  end
end

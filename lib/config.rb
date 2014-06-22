require_relative 'version'

module Onepush
  UNCHANGEABLE_PROPERTIES = %w(
    id
    web_server_type
    user
    app_dir
    passenger_enterprise
    passenger_force_install_from_source
  ).freeze

  CHANGEABLE_PROPERTIES = %w(
    type
    domain_names
    memcached
    redis
    ruby_version
    ruby_manager
    database_type
    database_name
    database_user
  ).freeze

  ALL_PROPERTIES =
    (UNCHANGEABLE_PROPERTIES +
    CHANGEABLE_PROPERTIES).freeze

  class << self
    def set_manifest_defaults(manifest)
      manifest['user'] ||= manifest['id']
      manifest['app_dir'] ||= "/var/www/#{manifest['id']}"

      manifest['database_type'] ||= 'postgresql'
      manifest['database_name'] ||= manifest['id']
      manifest['database_user'] = manifest['user']

      set_boolean_default(manifest, 'install_passenger', true)
      set_boolean_default(manifest, 'install_web_server', true)
      set_boolean_default(manifest, 'install_common_ruby_app_dependencies', true)

      set_boolean_default(manifest, 'memcached', false)
      set_boolean_default(manifest, 'redis', false)
      manifest['ruby_manager'] ||= 'rvm'
      manifest['web_server_type'] ||= 'nginx'

      set_boolean_default(manifest, 'passenger_enterprise', false)
      set_boolean_default(manifest, 'passenger_force_install_from_source', false)

      manifest['onepush_version'] = VERSION_STRING
      manifest['onepush_manifest_format_version'] = MANIFEST_FORMAT_VERSION_STRING

      # Bug check
      ALL_PROPERTIES.each do |name|
        if !manifest.has_key?(name)
          raise "Bug: didn't set default value for #{name}"
        end
      end
    end

  private
    def set_boolean_default(config, name, default)
      if !config.has_key?(name)
        config[name] = default
      end
    end
  end
end

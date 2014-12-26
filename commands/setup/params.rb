require_relative '../../lib/app_config'
require_relative '../../lib/infrastructure_config'
require_relative '../../lib/database_config'

module Pomodori
  module Commands
    # Works around https://github.com/intridea/hashie/issues/255
    module SetupParamsLike
      BooleanValue = Utils::BooleanValue

      def self.install_properties!(klass)
        klass.property :app_config, Pomodori::AppConfig

        klass.property :server_address, String
        klass.property :app_server_addresses, Array[String], default: []
        klass.property :db_server_address, String
        klass.property :external_database, DatabaseConfig

        klass.property :if_needed, BooleanValue, default: false
        klass.property :ssh_log, String
        klass.property :ssh_keys, Array[String], default: []
        klass.property :vagrant_key, String
        klass.property :progress, BooleanValue, default: false
        klass.property :progress_base, Float, default: 0
        klass.property :progress_ceil, Float, default: 1

        klass.property :install_passenger, BooleanValue, default: true
        klass.property :force_install_passenger_from_source, BooleanValue, default: false
        klass.property :install_web_server, BooleanValue, default: true
        klass.property :install_common_ruby_app_dependencies, BooleanValue, default: true
      end

      def install_database?
        app_config.database && external_database.nil?
      end

      def validate_and_finalize!
        if app_config.nil?
          abort "The parameter 'app_config' is required."
        end

        if server_address
          if app_server_addresses.any? || db_server_address
            abort "When the 'server_address' parameter is set, " +
              "'app_server_addresses' and 'db_server_address' may not be set."
          end
          self.app_server_addresses = [server_address]
          self.db_server_address = server_address
          self.server_address = nil
        else
          if app_server_addresses.empty?
            abort "The parameter 'app_server_addresses' is required."
          end
          if db_server_address.nil? && external_database.nil?
            abort "The parameter 'db_server_address' is required."
          end
        end

        if external_database && db_server_address
          abort "When the 'external_database' parameter is set, " +
            "'server_address' and 'db_server_address' may not be set."
        end

        if external_database
          external_database.validate_and_finalize!(app_config)
        end
      end
    end

    class SetupParams < Pomodori::InfrastructureConfig
      RESETUP_PROPERTIES = %w(
        external_database
      ).freeze

      include SetupParamsLike
      SetupParamsLike.install_properties!(self)
    end
  end
end

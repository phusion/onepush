require 'hashie/trash'
require 'hashie/extensions/ignore_undeclared'
require 'hashie/extensions/coercion'
require 'hashie/extensions/indifferent_access'
require 'hashie/extensions/dash/indifferent_access'
require_relative './utils/hashie_coerceable_property'
require_relative './utils/coercers'
require_relative './version'

module Pomodori
  class AppConfig < Hashie::Trash
    include Hashie::Extensions::IgnoreUndeclared
    include Hashie::Extensions::Coercion
    include Hashie::Extensions::Dash::IndifferentAccess
    extend Utils::HashieCoerceableProperty
    BooleanValue = Utils::BooleanValue
    def self.EnumValue(*args); Utils.EnumValue(*args); end


    ##### Unchangeable properties #####
    #
    # These properties are only used when a server is setup for the first time.
    # Their original values will be stored on the server. Once the server is setup,
    # the original values as stored on the server will be used, not the new values
    # in the config file.

    UNCHANGEABLE_PROPERTIES = %w(
      web_server_type
      user
      app_dir
      passenger_enterprise
      passenger_enterprise_download_token
    ).freeze

    property :web_server_type, String, default: 'nginx'
    property :user, String
    property :app_dir, String
    property :passenger_enterprise, BooleanValue, default: false
    property :passenger_enterprise_download_token, String, required: -> { passenger_enterprise }


    ##### Changeable properties ######
    #
    # These properties can be changed by the user at will. Pomodori will update
    # the server accordingly. If the value of one of these properties have changed,
    # then `pomodori deploy` will automatically call `pomodori setup` first.

    CHANGEABLE_PROPERTIES = %w(
      type
      domain_names
      deployment_ssh_keys
      postsetup_script

      passenger
      database
      memcached
      redis

      ruby_version
      ruby_manager
      rvm_min_version

      database_type
      database_name
      database_user
    ).freeze

    property :type, EnumValue(:type, 'ruby', 'nodejs'), default: 'ruby'
    property :domain_names, String, required: true
    property :deployment_ssh_keys, Array[String], default: []
    property :postsetup_script, Array[String], default: []

    property :passenger, BooleanValue, default: true
    property :database, BooleanValue, default: true
    property :memcached, BooleanValue, default: false
    property :redis, BooleanValue, default: false

    property :ruby_version, String, default: '2.1.5'
    property :ruby_manager, EnumValue(:ruby_manager, 'rvm'), default: 'rvm'
    property :rvm_min_version, String, default: '1.26.5'

    property :database_type, EnumValue(:database_type, 'postgresql'), default: 'postgresql'
    property :database_name, String
    property :database_user, String


    ################ Methods ################

    def set_defaults!(params)
      self.user ||= params.app_id
      self.app_dir ||= "/var/www/#{params.app_id}"
      self.database_user ||= params.app_id
      self.database_name ||= user
      self
    end

    def self.fixup_error_message(message)
      # Example message:
      # The property 'app_id' is required for Pomodori::InfrastructureConfig.
      #
      # Changes into:
      # The app config property 'app_id' is required.
      message = message.sub(/ for (.+?)$/, ".")
      message.sub!(/^The property /, "The app config property ")
      message
    end

    def to_server_app_config
      result = to_hash
      result['pomodori_version'] = VERSION_STRING
      result['pomodori_app_config_format_version'] = APP_CONFIG_FORMAT_VERSION_STRING
      result
    end
  end
end

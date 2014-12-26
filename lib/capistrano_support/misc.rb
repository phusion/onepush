module Pomodori
  module CapistranoSupport
    module Misc
      def create_user(host, name)
        case host.properties.fetch(:os_class)
        when :redhat
          sudo(host, "adduser #{name} && usermod -L #{name}")
        when :debian
          sudo(host, "adduser --disabled-password --gecos #{name} #{name}")
        else
          raise "Bug"
        end
      end

      def compare_version(a, b)
        parse_version(a) <=> parse_version(b)
      end

      def parse_version(version)
        version.split(/\./).map do |component|
          component.to_i
        end
      end

      def generate_server_manifest(setup_params, app_config)
        result = {
          'pomodori_version' => VERSION_STRING,
          'pomodori_setup_version' => SETUP_VERSION
        }
        Pomodori::Commands::SetupParams::RESETUP_PROPERTIES.each do |name|
          result[name] = setup_params[name]
        end
        result.merge!(app_config)
        result
      end
    end
  end
end

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

      def _check_setup_version_compatibility(host)
        last_version = try_download_to_string("/etc/pomodori/setup/last_run_version").to_s.strip
        last_version_name = try_download_to_string("/etc/pomodori/setup/last_run_version_name").to_s.strip
        last_setup_version = try_download_to_string("/etc/pomodori/setup/last_run_setup_version").to_s.strip
        if !last_version.empty? && last_version_name.empty?
          last_version_name = "#{POMODORI_APP_NAME} #{last_version}"
        end

        if !last_setup_version.empty?
          if Pomodori.setup_version_compatible?(last_setup_version)
            log_info "Compatibility check passed!"
          elsif Pomodori.setup_version_migratable?(last_setup_version)
            if last_version_name.empty?
              fatal_and_abort "The server #{host} was previously setup with an unknown " +
                "#{POMODORI_APP_NAME} version. But whatever that version was, it is " +
                "too different from the version that you're currently running " +
                "(#{Pomodori::VERSION_STRING}), so an explicit migration step is required.\n\n" +
                "Please run 'pomodori migrate' first."
            else
              fatal_and_abort "The server #{host} was previously setup with #{last_version_name}. " +
                "That version is too different from the version that you're currently running " +
                "(#{Pomodori::VERSION_STRING}), so an explicit migration step is required.\n\n" +
                "Please run 'pomodori migrate' first."
            end
          elsif last_version.empty?
            fatal_and_abort "The server #{host} was previously setup with an unknown " +
              "#{POMODORI_APP_NAME} version. But whatever that version was, it is " +
              "so different from the version that you're currently running " +
              "(#{Pomodori::VERSION_STRING}) that #{POMODORI_APP_NAME} is unable to continue. " +
              "You might be able to solve this problem by upgrading to the latest version of " +
              "#{POMODORI_APP_NAME}."
          elsif compare_version(Pomodori::VERSION_STRING, last_version) < 0
            # Server was setup with a newer version of Pomodori.
            fatal_and_abort "The server #{host} was previously setup with #{last_version_name}. " +
              "That version is too different from the version that you're currently running " +
              "(#{Pomodori::VERSION_STRING}), so #{POMODORI_APP_NAME} is unable to continue. " +
              "Please upgrade to the latest version of #{POMODORI_APP_NAME}."
          else
            # Server was setup with an older version of Pomodori.
            fatal_and_abort "The server #{host} was previously setup with #{last_version_name}. " +
              "That version is too different from the version that you're currently running " +
              "(#{Pomodori::VERSION_STRING}), so #{POMODORI_APP_NAME} is unable to continue. " +
              "Unfortunately, there is no migration path. Please use #{last_version_name} " +
              "on this server instead of newer versions."
          end
        end
      end
    end
  end
end

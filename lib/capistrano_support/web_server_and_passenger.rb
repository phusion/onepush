module Pomodori
  module CapistranoSupport
    module WebServerAndPassenger
      def autodetect_nginx(host)
        cache(host, :nginx) do
          result = {}
          if test("[[ -e /usr/sbin/nginx && -e /etc/nginx/nginx.conf ]]")
            result[:installed_from_system_package] = true
            result[:binary]      = "/usr/bin/nginx"
            result[:config_file] = "/etc/nginx/nginx.conf"
            result[:configtest_command] = "/etc/init.d/nginx configtest"
            result[:restart_command] = "/etc/init.d/nginx restart"
            result
          else
            files = capture("ls -1 /opt/*/*/nginx 2>/dev/null", :raise_on_non_zero_exit => false).split(/\r?\n/)
            if files.any?
              result[:binary] = files[0]
              result[:config_file] = File.absolute_path(File.dirname(files[0]) + "/../conf/nginx.conf")
              result[:configtest_command] = "#{files[0]} -t"
              has_runit_service = files[0] == "/opt/nginx/sbin/nginx" &&
                test("grep /opt/nginx/sbin/nginx /etc/service/nginx/run 2>&1")
              if has_runit_service
                result[:restart_command] = "sv restart /etc/service/nginx"
              end
              result
            else
              nil
            end
          end
        end
      end

      def autodetect_nginx!(host)
        autodetect_nginx(host) ||
          fatal_and_abort("Cannot autodetect Nginx. This is probably a bug in #{POMODORI_APP_NAME}. " +
            "Please report this to the authors.")
      end

      def autodetect_passenger(host)
        cache(host, :passenger) do
          ruby   = autodetect_ruby_interpreter_for_passenger(host)
          result = { :ruby => ruby }
          if test("[[ -e /usr/bin/passenger-config ]]")
            result[:installed_from_system_package] = true
            result[:bindir]            = "/usr/bin"
            result[:nginx_installer]   = "/usr/bin/passenger-install-nginx-module"
            result[:apache2_installer] = "/usr/bin/passenger-install-apache2-module"
            result[:config_command]    = "/usr/bin/passenger-config"
            result
          elsif test("[[ -e /opt/passenger/current/bin/passenger-config ]]")
            result[:bindir]            = "/opt/passenger/current/bin"
            result[:nginx_installer]   = "#{ruby} /opt/passenger/current/bin/passenger-install-nginx-module".strip
            result[:apache2_installer] = "#{ruby} /opt/passenger/current/bin/passenger-install-apache2-module".strip
            result[:config_command]    = "#{ruby} /opt/passenger/current/bin/passenger-config".strip
            result
          else
            begin
              passenger_config = capture("which passenger-config").strip
            rescue SSHKit::Command::Failed
              passenger_config = nil
            end
            if passenger_config
              bindir = File.dirname(passenger_config)
              result[:bindir] = bindir
              result[:nginx_installer]   = "#{bindir}/passenger-install-nginx-module"
              result[:apache2_installer] = "#{bindir}/passenger-install-apache2-module"
              result[:config_command]    = passenger_config
              result
            else
              nil
            end
          end
        end
      end

      def autodetect_passenger!(host)
        autodetect_passenger(host) || \
          fatal_and_abort("Cannot autodetect Phusion Passenger. This is probably a bug " +
            "in #{POMODORI_APP_NAME}. Please report this to the authors.")
      end

      def autodetect_ruby_interpreter_for_passenger(host)
        cache(host, :ruby) do
          if APP_CONFIG.type == 'ruby'
            # Since install_passenger_source_dependencies installs RVM
            # if the language is Ruby (and thus, does not install Rake
            # through the OS package manager), we must give RVM precedence
            # here.
            possibilities = [
              "/usr/local/rvm/wrappers/default/ruby",
              "/usr/bin/ruby"
            ]
          else
            possibilities = [
              "/usr/bin/ruby",
              "/usr/local/rvm/wrappers/default/ruby"
            ]
          end
          result = nil
          possibilities.each do |possibility|
            if test("[[ -e #{possibility} ]]")
              result = possibility
              break
            end
          end
          result
        end
      end

      def autodetect_ruby_interpreter_for_passenger!(host)
        autodetect_ruby_interpreter_for_passenger(host) || \
          fatal_and_abort("Unable to find a Ruby interpreter on the system. This is probably " +
            "a bug in #{POMODORI_APP_NAME}. Please report this to the authors.")
      end
    end
  end
end

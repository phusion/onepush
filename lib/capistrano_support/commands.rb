module Pomodori
  module CapistranoSupport
    module Commands
      def sudo(host, command, options = {})
        execute(wrap_in_sudo(host, command, options))
      end

      def sudo_test(host, command)
        test(wrap_in_sudo(host, command))
      end

      def sudo_capture(host, command)
        capture(wrap_in_sudo(host, command))
      end

      def wrap_in_sudo(host, command, options = {})
        if host.user == 'root'
          b(command, options)
        else
          if !host.properties.fetch(:sudo_checked)
            if test_cond("-e /usr/bin/sudo")
              if !test("/usr/bin/sudo -k -n true")
                fatal_and_abort "Sudo needs a password for the '#{host.user}' user. However, #{POMODORI_APP_NAME} " +
                  "needs sudo to *not* ask for a password. Please *temporarily* configure " +
                  "sudo to allow the '#{host.user}' user to run it without a password.\n\n" +
                  "Open the sudo configuration file:\n" +
                  "  sudo visudo\n\n" +
                  "Then insert:\n" +
                  "  # Remove this entry later. #{POMODORI_APP_NAME} only needs it temporarily.\n" +
                  "  #{host.user} ALL=(ALL) NOPASSWD: ALL"
              end
              host.properties.set(:sudo_checked, true)
            else
              fatal_and_abort "#{POMODORI_APP_NAME} requires 'sudo' to be installed on the server. Please install it first."
            end
          end
          "/usr/bin/sudo -k -n -H #{b(command, options)}"
        end
      end

      # A portable way to run condition tests using `[[`.
      # Unlike `test("[[ ... ]]")`, this method works both over
      # SSH and locally.
      def test_cond(condition)
        test(b "[[ #{condition} ]]")
      end

      def b(script, options = {})
        if options.fetch(:pipefail, true)
          full_script = "set -o pipefail && #{script}"
        else
          full_script = script
        end
        "/bin/bash -c #{Shellwords.escape(full_script)}"
      end
    end
  end
end

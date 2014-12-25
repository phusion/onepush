module Pomodori
  module CapistranoSupport
    module PackageManagement
      def force_apt_get_update_next_time(host)
        sudo(host, "rm -f /var/lib/apt/periodic/update-success-stamp")
        host.properties.set(:apt_get_updated, false)
      end

      def apt_get_update(host)
        sudo(host, "apt-get update -q && touch /var/lib/apt/periodic/update-success-stamp")
        host.properties.set(:apt_get_updated, true)
      end

      def apt_get_install(host, packages)
        packages = filter_non_installed_packages(host, packages)
        if !packages.empty?
          if !host.properties.fetch(:apt_get_updated)
            two_days = 2 * 60 * 60 * 24
            script = "[[ -e /var/lib/apt/periodic/update-success-stamp ]] && " +
              "timestamp=`stat -c %Y /var/lib/apt/periodic/update-success-stamp` && " +
              "threshold=`date +%s` && " +
              "(( threshold = threshold - #{two_days} )) && " +
              '[[ "$timestamp" -gt "$threshold" ]]'
            if !test(script)
              apt_get_update(host)
            end
          end
          sudo(host, "apt-get install -y -q #{packages.join(' ')}")
        end
        packages.size
      end

      def yum_install(host, packages)
        packages = filter_non_installed_packages(host, packages)
        if !packages.empty?
          sudo(host, "yum install -y #{packages.join(' ')}")
        end
        packages.size
      end

      def check_packages_installed(host, names)
        result = {}
        case host.properties.fetch(:os_class)
        when :redhat
          installed = capture("rpm -q #{names.join(' ')} 2>&1 | grep 'is not installed$'; true")
          not_installed = installed.split(/\r?\n/).map { |x| x.sub(/^package (.+) is not installed$/, '\1') }
          names.each do |name|
            result[name] = !not_installed.include?(name)
          end
        when :debian
          installed = capture("dpkg-query -s #{names.join(' ')} 2>/dev/null | grep '^Package: '; true")
          installed = installed.gsub(/^Package: /, '').split(/\r?\n/)
          names.each do |name|
            result[name] = installed.include?(name)
          end
        else
          raise "Bug"
        end
        result
      end

      def filter_non_installed_packages(host, names)
        result = []
        check_packages_installed(host, names).each_pair do |name, installed|
          if !installed
            result << name
          end
        end
        result
      end
    end
  end
end

def log_sshkit(level, message)
  case level
  when :fatal
    level = SSHKit::Logger::FATAL
  when :error
    level = SSHKit::Logger::ERROR
  when :warn
    level = SSHKit::Logger::WARN
  when :info
    level = SSHKit::Logger::INFO
  when :debug
    level = SSHKit::Logger::DEBUG
  when :trace
    level = SSHKit::Logger::TRACE
  else
    raise "Bug"
  end
  SSHKit.config.output << SSHKit::LogMessage.new(level, message)
end

def fatal(message)
  log_sshkit(:fatal, message)
end

def notice(message)
  log_sshkit(:info, message)
end

def info(message)
  log_sshkit(:info, message)
end

def fatal_and_abort(message)
  fatal(message)
  abort
end


def check_config_requirements(config)
  ['name', 'type'].each do |key|
    if !config[key]
      fatal_and_abort("The '#{key}' option must be set")
    end
  end
  if config['passenger_enterprise'] && !config['passenger_enterprise_download_token']
    fatal_and_abort "If you set passenger_enterprise to true, then you must also set passenger_enterprise_download_token"
  end
end


def sudo(host, command)
  execute(wrap_in_sudo(host, command))
end

def sudo_test(host, command)
  test(wrap_in_sudo(host, command))
end

def sudo_capture(host, command)
  capture(wrap_in_sudo(host, command))
end

def wrap_in_sudo(host, command)
  if host.user == 'root'
    b(command)
  else
    if !host.properties.fetch(:sudo_checked)
      if test("[[ -e /usr/bin/sudo ]]")
        if !test("/usr/bin/sudo -k -n true")
          fatal_and_abort "Sudo needs a password for the '#{host.user}' user. However, Flippo " +
            "needs sudo to *not* ask for a password. Please *temporarily* configure " +
            "sudo to allow the '#{host.user}' user to run it without a password.\n\n" +
            "Open the sudo configuration file:\n" +
            "  sudo visudo\n\n" +
            "Then insert:\n" +
            "  # Remove this entry later. Flippo only needs it temporarily.\n" +
            "  #{host.user} ALL=(ALL) NOPASSWD: ALL"
        end
        host.properties.set(:sudo_checked, true)
      else
        fatal_and_abort "Flippo requires 'sudo' to be installed on the server. Please install it first."
      end
    end
    "/usr/bin/sudo -k -n -H #{b command}"
  end
end

def b(script)
  full_script = "set -o pipefail && #{script}"
  "/bin/bash -c #{Shellwords.escape(full_script)}"
end

def mktempdir(host)
  tmpdir = capture("mktemp -d /tmp/flippo.XXXXXXXX").strip
  begin
    yield tmpdir
  ensure
    sudo(host, "rm -rf #{tmpdir}")
  end
end

def sudo_upload(host, io, path)
  mktempdir(host) do |tmpdir|
    upload!(io, "#{tmpdir}/file")
    sudo(host, "chown root: #{tmpdir}/file && mv #{tmpdir}/file #{path}")
  end
end


def cache(host, name)
  if result = host.properties.fetch("cache_#{name}")
    result[0]
  else
    result = [yield]
    host.properties.set("cache_#{name}", result)
    result[0]
  end
end

def clear_cache(host, name)
  host.properties.set("cache_#{name}", nil)
end


def apt_get_update(host)
  sudo(host, "apt-get update && touch /var/lib/apt/periodic/update-success-stamp")
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
    sudo(host, "apt-get install -y #{packages.join(' ')}")
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
    not_installed = installed.split("\n").map { |x| x.sub(/^package (.+) is not installed$/, '\1') }
    names.each do |name|
      result[name] = !not_installed.include?(name)
    end
  when :debian
    installed = capture("dpkg-query -s #{names.join(' ')} 2>/dev/null | grep '^Package: '; true")
    installed = installed.gsub(/^Package: /, '').split("\n")
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


def autodetect_nginx!(host)
  result = {}
  if test("[[ -e /usr/bin/nginx && -e /etc/nginx/nginx.conf ]]")
    result[:installed_from_system_package] = true
    result[:binary]      = "/usr/bin/nginx"
    result[:config_file] = "/etc/nginx/nginx.conf"
  elsif test("[[ -e /opt/nginx/sbin/nginx && -e /opt/nginx/conf/nginx.conf ]]")
    result[:binary]      = "/opt/nginx/sbin/nginx"
    result[:config_file] = "/opt/nginx/conf/nginx.conf"
  else
    fatal_and_abort("Cannot autodetect Nginx. This is probably a bug in Flippo. " +
      "Please report this to the authors.")
  end
  result
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
      passenger_config = capture("which passenger-config", :raise_on_non_zero_exit => false).strip
      if passenger_config.empty?
        nil
      else
        bindir = File.dirname(passenger_config)
        result[:bindir] = bindir
        result[:nginx_installer]   = "#{bindir}/passenger-install-nginx-module"
        result[:apache2_installer] = "#{bindir}/passenger-install-apache2-module"
        result[:config_command]    = passenger_config
        result
      end
    end
  end
end

def autodetect_passenger!(host)
  autodetect_passenger(host) || \
    fatal_and_abort("Cannot autodetect Phusion Passenger. This is probably a bug in Flippo. " +
      "Please report this to the authors.")
end

def autodetect_ruby_interpreter_for_passenger(host)
  cache(host, :ruby) do
    if CONFIG['type'] == 'ruby'
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
      "a bug in Flippo. Please report this to the authors.")
end

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


def b(script)
  full_script = "set -o pipefail && #{script}"
  "/bin/bash -c #{Shellwords.escape(full_script)}"
end


def apt_get_update(host)
  execute "apt-get update && touch /var/lib/apt/periodic/update-success-stamp"
  host.add_property(:apt_get_updated, true)
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
    execute "apt-get install -y #{packages.join(' ')}"
  end
  packages.size
end

def yum_install(host, packages)
  execute "yum install -y #{packages.join(' ')}"
end

def check_packages_installed(host, names)
  case host.properties.fetch(:os_class)
  when :redhat
    raise "TODO"
  when :debian
    result = {}
    installed = capture("dpkg-query -s #{names.join(' ')} 2>/dev/null | grep '^Package: '; true")
    installed = installed.gsub(/^Package: /, '').split("\n")
    names.each do |name|
      result[name] = installed.include?(name)
    end
    result
  else
    raise "Bug"
  end
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


def autodetect_nginx!
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

def autodetect_passenger!
  ruby   = autodetect_ruby_interpreter_for_passenger!
  result = { :ruby => ruby }
  if test("[[ -e /usr/bin/passenger-config ]]")
    result[:installed_from_system_package] = true
    result[:nginx_installer]   = "/usr/bin/passenger-install-nginx-module"
    result[:apache2_installer] = "/usr/bin/passenger-install-apache2-module"
    result[:config_command]    = "/usr/bin/passenger-config"
  elsif test("[[ -e /opt/passenger/current/bin/passenger-config ]]")
    result[:nginx_installer]   = "#{ruby} /opt/passenger/current/bin/passenger-install-nginx-module"
    result[:apache2_installer] = "#{ruby} /opt/passenger/current/bin/passenger-install-apache2-module"
    result[:config_command]    = "#{ruby} /opt/passenger/current/bin/passenger-config"
  else
    fatal_and_abort("Cannot autodetect Phusion Passenger. This is probably a bug in Flippo. " +
      "Please report this to the authors.")
  end
  result
end

def autodetect_ruby_interpreter_for_passenger!
  if test("[[ -e /usr/bin/ruby ]]")
    "/usr/bin/ruby"
  elsif test("[[ -e /usr/local/rvm/wrappers/default/ruby ]]")
    "/usr/local/rvm/wrappers/default/ruby"
  else
    abort "Unable to find a Ruby interpreter on the system. This is probably " +
      "a bug in Flippo. Please report this to the authors."
  end
end

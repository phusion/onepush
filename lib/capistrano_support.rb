require_relative './my_pretty_formatter'

ROOT = File.absolute_path(File.dirname(__FILE__) + "/..")
LOGGER = Logger.new(STDOUT)
REPORT_PROGRESS = ENV['REPORT_PROGRESS']
$progress_base = ENV.fetch('PROGRESS_BASE', 0).to_f
$progress_ceil = ENV.fetch('PROGRESS_CEIL', 1).to_f
$current_progress = 0

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

def log_terminal(level, message)
  if SSHKit.config.output.original_output != STDOUT
    printf "%-6s -- %s\n", level.to_s.upcase, message
  end
end

def fatal(message)
  log_sshkit(:fatal, message)
  log_terminal(:fatal, message)
end

def notice(message)
  log_sshkit(:info, message)
  log_terminal(:notice, message)
end

def info(message)
  log_sshkit(:info, message)
  log_terminal(:info, message)
end

def fatal_and_abort(message)
  fatal(message)
  abort
end

def report_progress(step, total)
  if REPORT_PROGRESS
    fraction = (step / total.to_f) * ($progress_ceil - $progress_base)
    $current_progress = $progress_base + fraction
    puts "PROGRS -- #{$current_progress}"
  end
end


def check_manifest_requirements(manifest)
  ['id', 'type', 'domain_names'].each do |key|
    if !manifest[key]
      fatal_and_abort("The '#{key}' option must be set")
    end
  end
  if manifest['passenger_enterprise'] && !manifest['passenger_enterprise_download_token']
    fatal_and_abort("If you set passenger_enterprise to true, then you must also " +
      "set passenger_enterprise_download_token")
  end
end

def initialize_onepush_capistrano
  if path = ENV['SSHKIT_OUTPUT']
    output = File.open(path, "a")
    output.sync = true
  else
    output = STDOUT
  end
  SSHKit.config.output = Onepush::MyPrettyFormatter.new(output)
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

def sudo_download(host, path, io)
  mktempdir(host) do |tmpdir|
    e_tmpdir = Shellwords.escape(tmpdir)
    e_path = Shellwords.escape(path)
    username = host.user || "root"
    sudo(host, "cp #{e_path} #{e_tmpdir}/file && chown #{username}: #{e_tmpdir} #{e_tmpdir}/file")
    download!("#{tmpdir}/file", io)
  end
end

def sudo_download_to_string(host, path)
  io = StringIO.new
  io.binmode
  sudo_download(host, path, io)
  io.string
end

def sudo_upload(host, io, path, options = {})
  mktempdir(host) do |tmpdir|
    chown = options[:chown] || "root:"
    chmod = options[:chmod] || "600"
    upload!(io, "#{tmpdir}/file")
    sudo(host, "chown #{chown} #{tmpdir}/file && chmod #{chmod} #{tmpdir}/file && mv #{tmpdir}/file #{path}")
  end
end

def wrap_in_sudo(host, command)
  if host.user == 'root'
    b(command)
  else
    if !host.properties.fetch(:sudo_checked)
      if test("[[ -e /usr/bin/sudo ]]")
        if !test("/usr/bin/sudo -k -n true")
          fatal_and_abort "Sudo needs a password for the '#{host.user}' user. However, Onepush " +
            "needs sudo to *not* ask for a password. Please *temporarily* configure " +
            "sudo to allow the '#{host.user}' user to run it without a password.\n\n" +
            "Open the sudo configuration file:\n" +
            "  sudo visudo\n\n" +
            "Then insert:\n" +
            "  # Remove this entry later. Onepush only needs it temporarily.\n" +
            "  #{host.user} ALL=(ALL) NOPASSWD: ALL"
        end
        host.properties.set(:sudo_checked, true)
      else
        fatal_and_abort "Onepush requires 'sudo' to be installed on the server. Please install it first."
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
  tmpdir = capture("mktemp -d /tmp/onepush.XXXXXXXX").strip
  begin
    yield tmpdir
  ensure
    sudo(host, "rm -rf #{tmpdir}")
  end
end

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


def force_apt_get_update_next_time(host)
  sudo(host, "rm -f /var/lib/apt/periodic/update-success-stamp")
  host.properties.set(:apt_get_updated, false)
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
      else
        nil
      end
    end
  end
end

def autodetect_nginx!(host)
  autodetect_nginx(host) ||
    fatal_and_abort("Cannot autodetect Nginx. This is probably a bug in Onepush. " +
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
    fatal_and_abort("Cannot autodetect Phusion Passenger. This is probably a bug in Onepush. " +
      "Please report this to the authors.")
end

def autodetect_ruby_interpreter_for_passenger(host)
  cache(host, :ruby) do
    if MANIFEST['type'] == 'ruby'
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
      "a bug in Onepush. Please report this to the authors.")
end


def edit_section_in_string(str, section_name, content)
  section_begin_str = "###### BEGIN #{section_name} ######"
  section_end_str   = "###### END #{section_name} ######"

  lines = str.split("\n", -1)
  content.chomp!

  start_index = lines.find_index(section_begin_str)
  if !start_index
    # Section is not in file.
    return if content.empty?
    lines << section_begin_str
    lines << content
    lines << section_end_str
  else
    end_index = start_index + 1
    while end_index < lines.size && lines[end_index] != section_end_str
      end_index += 1
    end
    if end_index == lines.size
      # End not found. Pretend like the section is empty.
      end_index = start_index
    end
    lines.slice!(start_index, end_index - start_index + 1)
    if !content.empty?
      lines.insert(start_index, section_begin_str, content, section_end_str)
    end
  end

  if lines.last && lines.last.empty?
    lines.pop
  end
  lines.join("\n") << "\n"
end

def sudo_edit_section(host, path, section_name, content, options)
  if sudo_test(host, "[[ -e #{path} ]]")
    str = sudo_download_to_string(host, path)
  else
    str = ""
  end
  io = StringIO.new
  io.binmode
  io.write(edit_section_in_string(str, section_name, content))
  io.rewind
  sudo_upload(host, io, path, options)
end

def check_file_change(host, path)
  md5_old = sudo_capture(host, "md5sum #{path} 2>/dev/null; true").strip
  yield
  md5_new = sudo_capture(host, "md5sum #{path}").strip
  md5_old != md5_new
end


def _check_server_setup(host)
  notice "Checking server setup..."
  report_progress(1, TOTAL_STEPS)

  if !check_server_setup_and_return_result(host)
    notice "Configuration changed. Re-setting up server..."
    env = ENV.to_hash.dup
    env["PROGRESS_BASE"] = $current_progress.to_s
    env["PROGRESS_CEIL"] = "0.5"
    if ENV["SSHKIT_OUTPUT"]
      env["SSHKIT_OUTPUT"] = ENV["SSHKIT_OUTPUT"]
    end
    if !system(env, "bundle", "exec", "cap", "production", "setup", :chdir => "#{ROOT}/setup")
      # Abort without printing backtrace.
      exit!
    end
    $progress_base = 0.5

    if !check_server_setup_and_return_result(host)
      fatal_and_abort "The server must be re-setup. Please run 'onepush setup'."
    end
  end
end

def check_server_setup_and_return_result(host)
  id = MANIFEST['id']
  set :application, id

  # Infer app dir
  app_dir = capture("readlink /etc/onepush/apps/#{id}; true").strip
  if app_dir.empty?
    return false
  end
  set(:deploy_to, app_dir)
  set(:repo_url, "#{app_dir}/onepush_repo")

  # Download previous setup manifest
  io = StringIO.new
  download!("#{app_dir}/onepush-setup.json", io)
  server_manifest = JSON.parse(io.string)
  set(:onepush_manifest, server_manifest)

  # Check whether the requested Ruby version is installed
  if MANIFEST['ruby_version']
    set :rvm_ruby_version, MANIFEST['ruby_version']
  end
  Rake::Task['rvm:hook'].reenable
  invoke 'rvm:hook'
  rvm_path = fetch(:rvm_path)
  ruby_version = fetch(:rvm_ruby_version)
  if !test("#{rvm_path}/bin/rvm #{ruby_version} do ruby --version")
    return false
  end

  # Check whether anything else has been changed, and thus requires
  # a new 'onepush setup' call
  Onepush::CHANGEABLE_PROPERTIES.each do |name|
    if MANIFEST[name] != server_manifest[name]
      return false
    end
  end

  true
end

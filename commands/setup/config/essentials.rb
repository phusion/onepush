task :autodetect_os do
  log_notice "Autodetecting operating system..."
  on roles(:app, :db) do |host|
    if test_cond("-e /etc/redhat-release || -e /etc/centos-release")
      fatal_and_abort "Red Hat and CentOS are not supported right now."
      host.set(:os_class, :redhat)

      info = capture("cat /etc/redhat-release").gsub("\r\n", "\n")
      info =~ /release (.+?) /
      distro_version = $1
      if distro_version
        host.set(:os_version, distro_version)
      else
        fatal_and_abort "Unable to autodetect Red Hat operating system version."
      end

      if info =~ /Red Hat/
        log_notice "Red Hat #{distro_version} detected."
        host.set(:os, :redhat)
        if distro_version < '6.4'
          fatal_and_abort "#{POMODORI_APP_NAME} only supports Red Hat 6.4 and later."
        end
      elsif info =~ /CentOS/
        log_notice "CentOS #{distro_version} detected."
        host.set(:os, :centos)
        if distro_version < '6.4'
          fatal_and_abort "#{POMODORI_APP_NAME} only supports CentOS 6.4 and later."
        end
      elsif info =~ /Amazon/
        log_notice "Amazon Linux #{distro_version} detected."
        host.set(:os, :amazon_linux)
      else
        log_notice "Unknown Red Hat derivative detected."
        fatal_and_abort "#{POMODORI_APP_NAME} only supports Red Hat, CentOS and Amazon Linux, not any other Red Hat derivatives."
      end

    elsif test_cond("-e /etc/system-release") && (info = capture("cat /etc/system-release")) =~ /Amazon/
      fatal_and_abort "Amazon Linux is not supported right now."
      host.set(:os_class, :redhat)
      host.set(:os, :amazon_linux)

      info.gsub!("\r\n", "\n")
      info =~ /release (.+?) /
      distro_version = $1
      if distro_version
        host.set(:os_version, distro_version)
        log_notice "Amazon Linux #{distro_version} detected."
      else
        fatal_and_abort "Unable to autodetect Amazon Linux version."
      end

    elsif test_cond("-e /usr/bin/apt-get")
      host.set(:os_class, :debian)
      apt_get_install(host, %w(lsb-release))

      lsb_info = capture("lsb_release -a")
      lsb_info.gsub!("\r\n", "\n")
      lsb_info =~ /Release:(.*)/
      distro_version = $1.strip
      lsb_info =~ /Distributor ID:(.*)/
      distributor_id = $1.strip
      host.set(:lsb_info, lsb_info)
      host.set(:os_version, distro_version)

      if distributor_id =~ /ubuntu/i
        log_notice "Ubuntu #{distro_version} detected."
        host.set(:os, :ubuntu)
        if distro_version < "12.04"
          fatal_and_abort "#{POMODORI_APP_NAME} only supports Ubuntu 12.04 and later."
        end
      elsif distributor_id =~ /debian/i
        log_notice "Debian #{distro_version} detected."
        host.set(:os, :debian)
        if distro_version < "7"
          fatal_and_abort "#{POMODORI_APP_NAME} only supports Debian 7 and later."
        end
      else
        log_notice "Unknown Debian derivative detected."
        fatal_and_abort "#{POMODORI_APP_NAME} only supports Debian and Ubuntu, not any other Debian derivatives."
      end

    else
      fatal_and_abort "Unsupported server operating system. #{POMODORI_APP_NAME} only " +
        "supports Ubuntu."
      #fatal_and_abort "Unsupported server operating system. #{POMODORI_APP_NAME} only " +
      #  "supports Red Hat, CentOS, Amazon Linux, Debian and Ubuntu."
    end

    arch = capture("/bin/uname -p").strip
    # On some systems 'uname -p' returns something like
    # 'Intel(R) Pentium(R) M processor 1400MHz' or
    # 'Intel(R)_Xeon(R)_CPU___________X7460__@_2.66GHz'.
    if arch == "unknown" || arch =~ / / || arch =~ /Hz$/
      arch = capture("/bin/uname -m").strip
    end
    host.set(:arch, arch)

    if arch =~ /^i.86$/ || arch == "x86"
      log_notice "x86 architecture detected."
      host.set(:normalized_arch, "x86")
    elsif arch == "amd64" || arch == "x86_64"
      log_notice "x86_64 architecture detected."
      host.set(:normalized_arch, "x86_64")
    else
      fatal_and_abort "Unsupported machine architecture #{arch.inspect}. " +
        "#{POMODORI_APP_NAME} only supports x86 and x86_64."
    end
  end
end

task :install_essentials => :autodetect_os do
  log_notice "Installing essentials..."

  on roles(:app) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      yum_install(host, %w(coreutils git sudo curl which gcc gcc-c++ make))
    when :debian
      apt_get_install(host, %w(coreutils git sudo curl debianutils apt-transport-https
        ca-certificates gnupg lsb-release build-essential))
    else
      raise "Bug"
    end
  end

  on roles(:db) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      yum_install(host, %w(sudo))
    when :debian
      apt_get_install(host, %w(sudo apt-transport-https ca-certificates lsb-release))
    else
      raise "Bug"
    end
  end

  on roles(:app, :db) do |host|
    sudo(host, "mkdir -p /etc/pomodori && chmod 755 /etc/pomodori")
    sudo(host, "mkdir -p /var/run/pomodori && chmod 700 /var/run/pomodori")
    if host.properties.fetch(:os_class) == :redhat
      enable_epel(host)
      enable_phusion_runit_yum_repo(host)
    end
  end
end

def enable_epel(host)
  if !test_cond("-e /etc/yum.repos.d/epel.repo")
    case host.properties.fetch(:normalized_arch)
    when "x86"
      epel_arch = "i386"
    when "x86_64"
      epel_arch = "x86_64"
    end
    case host.properties.fetch(:os_version)
    when /^6\./
      epel_major_version = "6"
      epel_version = "6-8"
    when /^7\./
      epel_major_version = "beta/7"
      epel_version = "7-0.1"
    else
      fatal_and_abort "Unable to enable EPEL automatically. Please do it manually."
    end

    log_info "Installing EPEL release #{epel_version} for #{epel_arch}..."
    epel_rpm_url = "http://download.fedoraproject.org/pub/epel/#{epel_major_version}/#{epel_arch}/epel-release-#{epel_version}.noarch.rpm"
    sudo(host, "rpm -Uvh #{epel_rpm_url}")
  end

  io = StringIO.new
  download!("/etc/yum.repos.d/epel.repo", io)
  io.string =~ /(.*)(\[epel\].*)/m
  preconfig  = $1
  subconfig  = $2

  if subconfig =~ /enabled *= *0/
    subconfig.sub!(/enabled *= *0/, 'enabled=1')
    io = StringIO.new
    io.puts("#{preconfig}#{subconfig}")
    io.rewind
    sudo_upload(host, io, "/etc/yum.repos.d/epel.repo")
    sudo(host, "chmod 644 /etc/yum.repos.d/epel.repo")
  end
end

def enable_phusion_runit_yum_repo(host)
  if !test_cond("-e /etc/yum.repos.d/phusion-runit.repo")
    case host.properties.fetch(:normalized_arch)
    when "x86"
      epel_arch = "i386"
    when "x86_64"
      epel_arch = "x86_64"
    end

    if host.properties.fetch(:os) == :amazon_linux
      name = "amazon"
    else
      name = "el"
    end

    log_info "Installing Phusion Runit repo..."
    sudo(host, "curl --fail -L -o /etc/yum.repos.d/phusion-runit.repo https://oss-binaries.phusionpassenger.com/yumgems/phusion-runit/#{name}.repo")
  end
end

task :check_setup_version_compatibility => :install_essentials do
  log_notice "Checking for compatibility..."
  on roles(:app, :db) do |host|
    _check_setup_version_compatibility(host)
  end
end

task :check_server_empty => :autodetect_os do
  if PARAMS.check_server_empty
    non_empty_host = nil
    detected_component = nil

    on roles(:app) do |host|
      if !test_cond("-e /etc/pomodori/setup/checked")
        case APP_CONFIG.type
        when 'ruby'
          if test("which ruby")
            detected_component = "Ruby"
            non_empty_host = host
          end
        when 'nodejs'
          if test("which node")
            detected_component = "Node.js"
            non_empty_host = host
          end
        end
      end
    end

    if non_empty_host
      fatal_and_abort "#{POMODORI_APP_NAME} is supposed to be used on empty servers with " +
        "Ubuntu 14.04. The server #{non_empty_host} doesn't appear to be empty though: it " +
        "already has #{detected_component} installed. #{POMODORI_APP_NAME} therefore " +
        "refuses to operate.\n\n" +
        "If you are sure you want to continue using #{POMODORI_APP_NAME} on these servers," +
        "re-run #{POMODORI_APP_NAME} with --skip-server-empty-check."
    end
  end

  on roles(:app) do |host|
    sudo(host, "mkdir -p /etc/pomodori/setup && " +
      "touch /etc/pomodori/setup/checked")
  end
end

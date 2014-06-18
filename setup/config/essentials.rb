task :autodetect_os do
  on roles(:app, :db) do |host|
    if test("[[ -e /etc/redhat-release || -e /etc/centos-release ]]")
      host.set(:os_class, :redhat)
      notice "Red Hat or CentOS detected"

    elsif test("[[ -e /etc/system-release ]]") && capture("/etc/system-release") =~ /Amazon/
      host.set(:os_class, :redhat)
      notice "Amazon Linux detected"

    elsif test("[[ -e /usr/bin/apt-get ]]")
      host.set(:os_class, :debian)
      apt_get_install(host, %w(lsb-release))

      lsb_info = capture("lsb_release -a")
      lsb_info =~ /Release:(.*)/
      distro_version = $1.strip
      lsb_info =~ /Distributor ID:(.*)/
      distributor_id = $1.strip
      host.set(:lsb_info, lsb_info)
      host.set(:os_version, distro_version)

      if distributor_id =~ /ubuntu/i
        notice "Ubuntu #{distro_version} detected"
        host.set(:os, :ubuntu)
        if distro_version < "12.04"
          fatal_and_abort "Flippo only supports Ubuntu 12.04 and later."
        end
      elsif distributor_id =~ /debian/i
        notice "Debian #{distro_version} detected"
        host.set(:os, :debian)
        if distro_version < "7"
          fatal_and_abort "Flippo only supports Debian 7 and later."
        end
      else
        notice "Unknown Debian derivative detected"
        fatal_and_abort "Flippo only supports Debian and Ubuntu, not any other Debian derivatives."
      end

    else
      abort "Unsupported server operating system. Flippo only supports Red Hat, CentOS, Amazon Linux, Debian and Ubuntu"
    end
  end
end

task :install_essentials => :autodetect_os do
  on roles(:app, :db) do
    execute "mkdir -p /var/run/flippo && chmod 700 /var/run/flippo"
  end

  on roles(:app) do |host|
    case host.properties.fetch(:os_class)
    when :redhat
      yum_install(host, %w(coreutils git sudo curl gcc g++ make))
    when :debian
      apt_get_install(host, %w(coreutils git sudo curl apt-transport-https ca-certificates lsb-release build-essential))
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
end

task :install_additional_services => :install_essentials do
  log_notice "Installing additional services..."

  on roles(:app) do |host|
    if APP_CONFIG.memcached
      case host.properties.fetch(:os_class)
      when :redhat
        yum_install(host, %w(memcached))
      when :debian
        apt_get_install(host, %w(memcached))
      else
        raise "Bug"
      end
    end
    if APP_CONFIG.redis
      case host.properties.fetch(:os_class)
      when :redhat
        yum_install(host, %w(redis))
      when :debian
        apt_get_install(host, %w(redis-server))
      else
        raise "Bug"
      end
    end
  end
end

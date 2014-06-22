task :install_addons => :install_essentials do
  notice "Installing addons..."
  addons = MANIFEST['addons'] || []

  on roles(:app) do |host|
    addons.each do |addon|
      case addon
      when "memcached"
        case host.properties.fetch(:os_class)
        when :redhat
          yum_install(host, %w(memcached))
        when :debian
          apt_get_install(host, %w(memcached))
        else
          raise "Bug"
        end
      when "redis"
        case host.properties.fetch(:os_class)
        when :redhat
          yum_install(host, %w(redis))
        when :debian
          apt_get_install(host, %w(redis-server))
        else
          raise "Bug"
        end
      else
        fatal_and_abort "Unsupported addon: #{addon}"
      end
    end
  end
end

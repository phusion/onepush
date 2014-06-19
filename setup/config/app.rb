task :create_app_user => :install_essentials do
  on roles(:app) do |host|
    name = CONFIG['user']
    if !test("id -u #{name}")
      case host.properties.fetch(:os_class)
      when :redhat
        sudo(host, "adduser #{name} && usermod -L #{name}")
      when :debian
        sudo(host, "adduser --disabled-password --gecos #{name} #{name}")
      else
        raise "Bug"
      end
    end
    case CONFIG['type']
    when 'ruby'
      case CONFIG['ruby_manager']
      when 'rvm'
        sudo(host, "usermod -a -G rvm #{name}")
      end
    end
  end
end

task :create_app_dir => [:install_essentials, :create_app_user] do
  path  = CONFIG['app_dir']
  owner = CONFIG['user']

  primary_dirs = "#{path} #{path}/releases #{path}/shared #{path}/flippo_repo"

  on roles(:app) do
    sudo(host, "mkdir -p #{primary_dirs} && chown #{owner}: #{primary_dirs} && chmod u=rwx,g=rx,o=x #{primary_dirs}")
    sudo(host, "mkdir -p #{path}/shared/config && chown #{owner}: #{path}/shared/config")
    sudo(host, "cd #{path}/flippo_repo && if ! [[ -e HEAD ]]; then sudo -u #{owner} -H git init --bare; fi")
  end
end

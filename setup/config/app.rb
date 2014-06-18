task :create_app_user => :install_essentials do
  on roles(:app) do
    name = CONFIG['user']
    if !test("id -u #{name}")
      execute "adduser", "--disabled-password", "--gecos", name, name
    end
    case CONFIG['type']
    when 'ruby'
      case CONFIG['ruby_manager']
      when 'rvm'
        execute "usermod -a -G rvm #{name}"
      end
    end
  end
end

task :create_app_dir => [:install_essentials, :create_app_user] do
  path  = CONFIG['app_dir']
  owner = CONFIG['user']

  primary_dirs = "#{path} #{path}/releases #{path}/shared #{path}/flippo_repo"

  on roles(:app) do
    execute "mkdir -p #{primary_dirs} && chown #{owner}: #{primary_dirs} && chmod u=rwx,g=rx,o=x #{primary_dirs}"
    execute "mkdir -p #{path}/shared/config && chown #{owner}: #{path}/shared/config"
    execute "cd #{path}/flippo_repo && if ! [[ -e HEAD ]]; then sudo -u #{owner} -H git init --bare; fi"
  end
end

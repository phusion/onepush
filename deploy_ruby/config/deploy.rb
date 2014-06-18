set :application, 'my_app_name'
set :repo_url, CONFIG['app_dir'] + '/flippo_repo'

# Default branch is :master
# ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }.call

# Default deploy_to directory is /var/www/my_app
# set :deploy_to, '/var/www/my_app'

# Default value for :scm is :git
# set :scm, :git

# Default value for :format is :pretty
# set :format, :pretty

# Default value for :log_level is :debug
# set :log_level, :debug

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
set :linked_files, %w{config/database.yml config/secrets.yml}

# Default value for linked_dirs is []
# set :linked_dirs, %w{bin log tmp/pids tmp/cache tmp/sockets vendor/bundle public/system}

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for keep_releases is 5
# set :keep_releases, 5

namespace :deploy do
  # Override migrate task from capistrano-rails.
  # We add the ability to run db:schema:load instead of db:migrate.
  Rake::Task["deploy:migrate"].clear_actions
  task :migrate => [:set_rails_env] do
    on primary fetch(:migration_role) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          if fetch(:schema_load)
            execute :rake, "db:schema:load"
          else
            execute :rake, "db:migrate"
          end
        end
      end
    end
  end

  desc 'Push code to app servers'
  task :push_code do
    run_locally do
      revision=`git rev-parse --abbrev-ref HEAD`.strip
      repo_path = CONFIG['app_dir'] + '/flippo_repo'
      # also set key etc
      #execute "git push #{server_address}:#{repo_path} #{revision}:master"
    end
  end

  task :check_server_setup do
    on roles(:app) do
      name = CONFIG['name']
      if !test("-h /etc/flippo/apps/#{name}")
        fatal_and_abort "The server isn't correctly setup yet. Please run 'flippo setup'."
      end
    end
  end

  before :starting, :push_code
  before :starting, :check_server_setup

  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      execute :touch, release_path.join('tmp/restart.txt')
    end
  end

  after :publishing, :restart

  after :restart, :clear_cache do
    on roles(:web), in: :groups, limit: 3, wait: 10 do
      within release_path do
        execute :rake, 'cache:clear'
      end
    end
  end
end

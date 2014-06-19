set :application, CONFIG['name']
set :deploy_to, CONFIG['app_dir']
set :repo_url, CONFIG['app_dir'] + '/flippo_repo'
if CONFIG['ruby_version']
  set :rvm_ruby_version, CONFIG['ruby_version']
end

# Default branch is :master
# ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }.call

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
    revision  = `git rev-parse --abbrev-ref HEAD`.strip
    repo_path = fetch(:repo_url)

    on roles(:app, :in => :sequence) do |host|
      Dir.mktmpdir do |tmpdir|
        File.open("#{tmpdir}/ssh_wrapper", "w") do |f|
          f.puts "#!/bin/sh"
          f.write "exec ssh "
          if host.netssh_options[:forward_agent]
            f.write "-A "
          end
          if host.netssh_options[:keys]
            host.netssh_options[:keys].each do |key|
              f.write "-i #{Shellwords.escape(File.absolute_path(key))} "
            end
          end
          f.write "\"$@\"\n"
        end

        ssh_wrapper = "#{tmpdir}/ssh_wrapper"
        File.chmod(0700, ssh_wrapper)

        git_host = "ssh://"
        if host.user
          git_host << "#{host.user}@"
        end
        git_host << host.hostname
        if host.port
          git_host << ":#{host.port}"
        else
          git_host << ":"
        end

        run_locally do
          execute "env GIT_SSH=#{Shellwords.escape ssh_wrapper} " +
            "git push #{git_host}#{repo_path} #{revision}:master -f"
        end
      end
    end
  end

  before :starting, :push_code

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

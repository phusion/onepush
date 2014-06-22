# Default value for :linked_files is []
set :linked_files, %w{config/database.yml config/secrets.yml}

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

  desc 'Sanity check codebase'
  task :check_codebase do
    gemfile_lock = `git show HEAD:Gemfile.lock`
    config = fetch(:onepush_setup)

    case config['database_type']
    when 'postgresql'
      if gemfile_lock !~ / pg /
        fatal_and_abort "Onepush uses PostgreSQL as database. However, your " +
          "app does not include the PostgreSQL driver. Please add this to your Gemfile:\n" +
          "  gem 'pg'\n\n" +
          "Then run 'bundle install', then run 'onepush deploy' again."
      end
    else
      fatal_and_abort "Unsupported database type. Only PostgreSQL is supported."
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

  before :starting, :check_codebase
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
        execute :rake, 'tmp:clear'
      end
    end
  end


  ###### Progress reporting hooks ######
  
  TOTAL_STEPS = 8.0

  before :starting, :report_progress_starting do
    notice "Running sanity checks..."
    report_progress(1, TOTAL_STEPS)
  end

  before :updating, :report_progress_updating do
    notice "Copying files for new release..."
    report_progress(2, TOTAL_STEPS)
  end

  before '^bundler:install', :report_progress_bundle_install do
    notice "Installing gem bundle..."
    report_progress(3, TOTAL_STEPS)
  end

  before :compile_assets, :report_progress_compile_assets do
    notice "Compiling assets..."
    report_progress(4, TOTAL_STEPS)
  end

  before :normalize_assets, :report_progress_normalize_assets do
    notice "Normalizing assets..."
    report_progress(5, TOTAL_STEPS)
  end

  before :migrate, :report_progress_migrate do
    notice "Running database migrations..."
    report_progress(6, TOTAL_STEPS)
  end

  before :reverting, :report_progress_reverting do
    notice "Reverting to previous release..."
    report_progress((TOTAL_STEPS - 1), TOTAL_STEPS)
  end

  before :finishing, :report_progress_finishing do
    notice "Finalizing release..."
    report_progress((TOTAL_STEPS - 1), TOTAL_STEPS)
  end

  after :finished, :report_progress_finished do
    notice "Finished!"
    report_progress(TOTAL_STEPS, TOTAL_STEPS)
  end
end

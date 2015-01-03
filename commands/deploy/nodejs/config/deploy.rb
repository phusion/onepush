set :linked_files, %w{config/database.yml config/database.json config/secrets.yml}
set :linked_dirs, %w{log tmp}
set :npm_flags, '--production --no-spin'
set :npm_roles, :app

namespace :deploy do
  after :updating, :upload_local_config_files do
    on roles(:app) do
      # We do not put these files in the shared dir. The original
      # files are probably in version control, so on the server they
      # should be tied to a specific release.
      Dir[File.join(PARAMS.app_root, "config", "*.pomodori")].each do |path|
        basename = File.basename(path, ".pomodori")
        subpath  = File.join("config", basename)
        upload!(path, release_path.join(subpath))
        execute :chmod, "600", release_path.join(subpath)
      end
    end
  end

  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do |host|
      if APP_CONFIG.passenger
        passenger_info = autodetect_passenger(host)
        if passenger_info
          passenger_config = passenger_info[:config_command]
          execute "sudo -k -n -H #{passenger_config} restart-app --ignore-app-not-running #{deploy_path}/"
        else
          execute :touch, release_path.join("tmp/restart.txt")
        end
      end
    end
  end

  after :publishing, :restart


  ###### Progress reporting hooks ######

  before :starting, :report_progress_starting do
    log_notice "Running sanity checks..."
    report_progress(2, TOTAL_STEPS)
  end

  before :updating, :report_progress_updating do
    log_notice "Copying files for new release..."
    report_progress(3, TOTAL_STEPS)
  end

  before '^npm:install', :report_progress_npm_install do
    log_notice "Installing NPM modules..."
    report_progress(4, TOTAL_STEPS)
  end

  before :restart, :report_progress_restart do
    log_notice "Restarting app..."
    report_progress(5, TOTAL_STEPS)
  end

  before :reverting, :report_progress_reverting do
    log_notice "Reverting to previous release..."
    report_progress((TOTAL_STEPS - 1), TOTAL_STEPS)
  end

  before :finishing, :report_progress_finishing do
    log_notice "Finalizing release..."
    report_progress((TOTAL_STEPS - 1), TOTAL_STEPS)
  end

  after :finished, :report_progress_finished do
    log_notice "Finished deploying app!"
    report_progress(TOTAL_STEPS, TOTAL_STEPS)
  end
end

Capistrano::Configuration.instance.load do
  require 'yaml'
  require File.dirname(__FILE__) + '/util'
  require File.dirname(__FILE__) + '/db'
  require File.dirname(__FILE__) + '/ferret' if (File.exist?('script/ferret_server') || File.exist?('script/ferret_start'))

  #TODO: Remove this when we migrate all of our apps to passenger
  require File.dirname(__FILE__) + (fetch(:using_passenger, true) ? '/deploy/passenger' : '/deploy/mongrel')

  set :app_symlinks,    nil
  set :keep_releases,   3
  set :use_sudo,        false
  set :rails_env,       'development'

  # Callbacks
  before "deploy",              "util:capture_pending_changes"
  after "deploy",               "deploy:cleanup"
  after "deploy",               "util:notify"
  after "deploy",               "util:notify_tracker"
  after "deploy:update_code",   "fusionary:symlink_configs"
  after "deploy:symlink",       "fusionary:symlink_extras"
  after "deploy:setup",         "fusionary:create_shared_config"
  after "deploy:setup",         "fusionary:setup_symlinks"

  namespace :fusionary do
    desc "symlink configs from shared to release directory"
    task :symlink_configs, :roles => [:web, :app] do
      %w[database.yml mongrel_cluster.yml settings.yml gmaps_api_key.yml].each do |config_file|
        run "ln -nfs #{shared_path}/config/#{config_file} #{release_path}/config"
      end
    end

    desc "create shared config directory"
    task :create_shared_config, :roles => [:app, :web] do
      run "mkdir -p #{shared_path}/config"
    end

    desc "Setup additional symlinks for app"
    task :setup_symlinks, :roles => [:app, :web] do
      if app_symlinks
        app_symlinks.each do |link|
          if link.split("/").last.include? "."
            run "mkdir -p #{shared_path}/#{File.dirname(link)}"
          else
            run "mkdir -p #{shared_path}/#{link}"
          end
        end
      end
    end

    task :symlink_extras, :roles => [:app, :web] do
      if app_symlinks
        app_symlinks.each { |link| run "ln -nfs #{shared_path}/#{link} #{current_path}/#{link}" }
      end
    end
  end
end

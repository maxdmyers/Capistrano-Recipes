require 'active_support'
require 'fileutils'

Capistrano::Configuration.instance.load do

  namespace :db do
    desc "Copy database from server to local machine"
    task :sync_to_local, :roles => [:db] do
      set_config_vars
      continue = Capistrano::CLI.ui.ask "This task will overwrite your existing #{rails_env} data. Proceed? (y/n)"
      if continue =~ /[Yy]/
        mysql_dump    = mysqldump(remote_dump_path,  remote_dbconfig['database'],
                                  :u => remote_dbconfig['username'], :p => remote_dbconfig['password'],
                                  :h => remote_dbconfig['host'], :compress => true, :ignore_tables => ENV["IGNORE_TABLES"])
        
        mysql_import  = mysqlimport(local_path, local_dbconfig['database'], :mysql_cmd => mysql_cmd,
                                    :u => local_dbconfig['username'], :p => local_dbconfig['password'],
                                    :h => local_dbconfig['host'], :compress => true)
        
        run mysql_dump do |ch, _, out|
          puts out
        end
        
        download remote_dump_path, local_path
        
        run "rm #{remote_dump_path}"
        
        `rake db:create`
        puts "Running local mysql import from #{rails_env} data..."
        `#{mysql_import}`
        
        `rm #{uncompressed_path(local_path)}`
      end
    end
    
    desc "Copy local database to server"
    task :sync_to_remote, :roles => [:db] do
      set_config_vars
      continue = Capistrano::CLI.ui.ask "CAUTION!!!! This task will overwrite your existing #{rails_env} data REMOTELY. Proceed? (y/N)"
      if continue =~ /[Yy]/
        mysql_dump    = mysqldump(local_path,  local_dbconfig['database'],
                                  :u => local_dbconfig['username'], :p => local_dbconfig['password'],
                                  :h => local_dbconfig['host'], :compress => true, :mysqldump_cmd => "mysqldump5", :ignore_tables => ENV["IGNORE_TABLES"])
        
        mysql_import  = mysqlimport(remote_dump_path, remote_dbconfig['database'], :mysql_cmd => "mysql",
                                    :u => remote_dbconfig['username'], :p => remote_dbconfig['password'],
                                    :h => remote_dbconfig['host'], :compress => true)
        
        `#{mysql_dump}`
        upload local_path, remote_dump_path
        
        puts "Running remote mysql import from #{rails_env} data..."
        run mysql_import
        run "rm #{uncompressed_path(remote_dump_path)}"
      end
    end
    
    def mysqldump(dumpfile, database, options={})
      cmd           = options.delete(:mysqldump_cmd) || "mysqldump"
      compress      = options.delete(:compress)
      ignore_tables = options.delete(:ignore_tables).to_s.split(/,| /).reject {|s| s.blank? }
      opts          = create_option_string(options)
      dump_cmd      = "#{cmd} #{opts} #{database}"
      dump_cmd     += " " + ignore_tables.map {|t| "--ignore-table=#{database}.#{t}"}.join(" ") if ignore_tables.any?
      dump_cmd     += " | gzip -f"  if compress
      dump_cmd     += " > #{dumpfile}"
    end
    
    def mysqlimport(dumpfile, database, options={})
      compress    = options.delete(:compress)
      cmd         = options.delete(:mysql_cmd) || "mysql"
      if compress
        import_cmd = "gunzip -f #{dumpfile} && "
        dumpfile = File.dirname(dumpfile) + "/" + File.basename(dumpfile, ".gz")
      else
        import_cmd = ""
      end
      
      import_cmd  += "#{cmd} #{create_option_string(options)} #{database} < #{dumpfile}"
    end
    
    def create_option_string(options)
      options.reject {|k, v| v.blank? }.inject([]) do |ary, (k, v)|
        # Due to lame mysql command like requirement
        ary << (k == :p ? "-#{k}#{v}" : "-#{k} #{v}")
      end.join(" ")
    end
    
    def uncompressed_path(orig_path)
      File.dirname(orig_path) + "/" + File.basename(orig_path, ".gz")
    end
    
    def set_config_vars
      set :database_yml_path,   fetch(:database_yml_path, "config/database.yml")
      set :mysql_cmd,           "mysql"
      
      database_yml = ""
      run "cat #{shared_path}/config/database.yml" do |_, _, database_yml| end
      set :rails_env,         'development'
      set :remote_dbconfig,   YAML::load(database_yml)[rails_env]
      set :local_dbconfig,    YAML::load(File.open(database_yml_path))[rails_env]
      set :remote_dump_path,  "#{current_path}/tmp/#{rails_env}_dump.sql.gz"
      
      FileUtils.mkdir_p(File.join(Dir.pwd, "tmp"))
      set :local_path,        'tmp/' + File.basename(remote_dump_path)
    end
  end 
end
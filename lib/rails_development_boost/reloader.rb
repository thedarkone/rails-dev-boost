module RailsDevelopmentBoost
  module Reloader # replacement for the Rails' post fa1d9a file_update_checker
    extend self
    
    def hook_in!
      Rails.application.reloaders.unshift(self)
      ActionDispatch::Reloader.to_prepare { RailsDevelopmentBoost::Reloader.execute_if_updated }
    end
    
    def execute
      init unless @inited
      @last_run_result = ActiveSupport::Dependencies.unload_modified_files!
    end
    
    def execute_if_updated
      @last_run_result.nil? ? execute : @last_run_result
    ensure
      @last_run_result = nil
    end

    alias_method :updated?, :execute
    
    private
    def init
      Rails.application.reloaders.delete_if {|reloader| rails_file_checker?(reloader)} # remove the Rails' default file_checker
      @inited = true
    end
    
    def rails_file_checker?(reloader)
      if (dir_glob = reloader.instance_variable_get(:@glob)).kind_of?(String)
        autoload_paths = ActiveSupport::Dependencies.autoload_paths
        dir_glob.sub(/\A\{/, '').sub(/\}\Z/, '').split(',').all? do |glob_path|
          autoload_paths.any? {|autoload_path| glob_path.starts_with?(autoload_path)}
        end
      end
    end
  end
end
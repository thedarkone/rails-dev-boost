module RailsDevelopmentBoost
  module Reloader # replacement for the Rails' post fa1d9a file_update_checker
    module RoutesReloaderPatch
      def force_execute!
        @force_execute = true
      end
      
      def updated?
        @force_execute = true if result = super
        result
      end
      
      def execute
        if RailsDevelopmentBoost.reload_routes_on_any_change || @in_execute_if_updated || @force_execute || updated?
          @force_execute = false
          super
        end
      end
      
      def execute_if_updated
        old_in_execute_if_updated = @in_execute_if_updated
        @in_execute_if_updated = true
        super
      ensure
        @in_execute_if_updated = old_in_execute_if_updated
      end
    end
    
    extend self
    
    def hook_in!
      Rails.application.reloaders.unshift(self)
      ActionDispatch::Reloader.to_prepare(:prepend => true) { RailsDevelopmentBoost::Reloader.execute_if_updated }
      patch_routes_reloader! if Rails::VERSION::MAJOR >= 4
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
    
    def routes_reloader
      Rails.application.respond_to?(:routes_reloader) && Rails.application.routes_reloader
    end
    
    private
    # Rails 4.0+ calls routes_reloader.execute instead of routes_reloader.execute_if_updated because an autoloaded Rails::Engine might be mounted via routes.rb, therefore if any constants
    # are unloaded this triggers the reloading of routes.rb, we would like to avoid that.
    def patch_routes_reloader!
      if reloader = routes_reloader
        reloader.extend(RoutesReloaderPatch)
      end
    end
    
    def init
      Rails.application.reloaders.delete_if do |reloader|
        if rails_file_checker?(reloader)
          pacify_rails_file_checker(reloader) # the checker's methods are still being called in AD::Reloader's to_prepare callback
          true # remove the Rails' default file_checker
        end
      end
      @inited = true
    end
    
    def pacify_rails_file_checker(file_checker)
      file_checker.singleton_class.class_eval do
        def updated?;           false; end
        def execute;            false; end
        def execute_if_updated; false; end
      end
    end
    
    def rails_file_checker?(reloader)
      if (dir_glob = reloader.instance_variable_get(:@glob)).kind_of?(String)
        autoload_paths = ActiveSupport::Dependencies.autoload_paths
        dir_glob.sub(/\A\{/, '').sub(/\}\Z/, '').split(',').all? do |glob_path|
          autoload_paths.any? {|autoload_path| glob_path.starts_with?(autoload_path.to_s)}
        end
      end
    end
  end
end
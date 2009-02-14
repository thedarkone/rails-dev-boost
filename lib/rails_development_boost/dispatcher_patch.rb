module RailsDevelopmentBoost
  module DispatcherPatch
    def self.apply!
      patch = self
      require 'action_controller'
      require 'action_controller/dispatcher'
      ActionController::Dispatcher.class_eval do
        to_prepare { ActiveSupport::Dependencies.unload_modified_files }
        remove_method :reload_application
        include patch
      end
    end
    
    # Overridden.
    def reload_application
      # Cleanup the application before processing the current request.
      # ActiveRecord::Base.reset_subclasses if defined?(ActiveRecord)
      # ActiveSupport::Dependencies.clear
      ActiveSupport::Dependencies.remove_explicitely_unloadable_constants!
      ActiveRecord::Base.clear_reloadable_connections! if defined?(ActiveRecord)

      # Run prepare callbacks before every request in development mode
      run_callbacks :prepare_dispatch

      ActionController::Routing::Routes.reload
    end
    
  end
end

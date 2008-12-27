module RailsDevelopmentBoost
  module DispatcherPatch
    def self.apply!
      patch = self
      require 'action_controller'
      require 'action_controller/dispatcher'
      ActionController::Dispatcher.class_eval do
        to_prepare { ActiveSupport::Dependencies.unload_modified_files }
        remove_method :cleanup_application
        include patch
      end
    end
    
    # Overridden.
    def cleanup_application
      #ActiveRecord::Base.reset_subclasses if defined?(ActiveRecord)
      ActiveSupport::Dependencies.remove_explicitely_unloadable_constants!
      ActiveRecord::Base.clear_reloadable_connections! if defined?(ActiveRecord)
    end
  end
end

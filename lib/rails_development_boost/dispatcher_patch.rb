module RailsDevelopmentBoost
  module DispatcherPatch
    def self.apply!
      patch = self
      require 'action_controller'
      require 'action_controller/dispatcher'
      ActionController::Dispatcher.to_prepare { ActiveSupport::Dependencies.unload_modified_files }
      ActionController::Dispatcher.singleton_class.class_eval do
        remove_method :cleanup_application
        include patch
      end
    end
    
    # Overridden
    def cleanup_application
      # Cleanup the application before processing the current request.
      # ActiveRecord::Base.reset_subclasses if defined?(ActiveRecord) #removed
      # ActiveSupport::Dependencies.clear #removed
      ActiveRecord::Base.clear_reloadable_connections! if defined?(ActiveRecord)
    end
  end
end

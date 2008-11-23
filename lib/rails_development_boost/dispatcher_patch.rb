module RailsDevelopmentBoost
  module DispatcherPatch
    def self.apply!
      require 'action_controller/dispatcher'
      
      patch = self
      ActionController::Dispatcher.class_eval do
        to_prepare do
          ActiveSupport::Dependencies.unload_modified_files
        end
        
        remove_method :cleanup_application
        include patch
      end
    end
    
    # Overridden.
    def cleanup_application
      #ActiveRecord::Base.reset_subclasses if defined?(ActiveRecord)
      #ActiveSupport::Dependencies.clear
      ActiveRecord::Base.clear_reloadable_connections! if defined?(ActiveRecord)
    end
  end
end

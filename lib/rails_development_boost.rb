module RailsDevelopmentBoost
  class Railtie < ::Rails::Railtie
    config.dev_boost = RailsDevelopmentBoost
    
    config.after_initialize do
      if boost_enabled?
        # this should go into ActiveSupport.on_load(:action_pack), alas Rails doesn't provide it
        if defined?(ActionDispatch::Reloader) # post 0f7c970
          ActionDispatch::Reloader.to_prepare { ActiveSupport::Dependencies.unload_modified_files! }
        else
          ActionDispatch::Callbacks.before    { ActiveSupport::Dependencies.unload_modified_files! }
        end
      end
    end
    
    def self.boost_enabled?
      !$rails_rake_task && (Rails.env.development? || (config.respond_to?(:soft_reload) && config.soft_reload))
    end
    
    def boost_enabled?
      self.class.boost_enabled?
    end
    
    initializer 'dev_boost.setup', :after => :load_active_support do |app|
      if boost_enabled?
        [DependenciesPatch, ReferencePatch, DescendantsTrackerPatch, ObservablePatch, ReferenceCleanupPatch].each(&:apply!)
        
        if defined?(AbstractController::Helpers)
          ViewHelpersPatch.apply!
        else
          ActiveSupport.on_load(:action_controller) { ViewHelpersPatch.apply! }
        end
      end
    end
  end
  
  autoload :DependenciesPatch,       'rails_development_boost/dependencies_patch'
  autoload :DescendantsTrackerPatch, 'rails_development_boost/descendants_tracker_patch'
  autoload :LoadedFile,              'rails_development_boost/loaded_file'
  autoload :ObservablePatch,         'rails_development_boost/observable_patch'
  autoload :ReferencePatch,          'rails_development_boost/reference_patch'
  autoload :ReferenceCleanupPatch,   'rails_development_boost/reference_cleanup_patch'
  autoload :RequiredDependency,      'rails_development_boost/required_dependency'
  autoload :ViewHelpersPatch,        'rails_development_boost/view_helpers_patch'
  
  def self.debug!
    DependenciesPatch.debug!
  end
end

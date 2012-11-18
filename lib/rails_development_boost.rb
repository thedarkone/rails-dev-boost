module RailsDevelopmentBoost
  class Railtie < ::Rails::Railtie
    config.dev_boost = RailsDevelopmentBoost
    
    config.after_initialize do
      if boost_enabled?
        # this should go into ActiveSupport.on_load(:action_pack), alas Rails doesn't provide it
        if supports_reload_classes_only_on_change? # post fa1d9a
          Rails.application.config.reload_classes_only_on_change = true
          Reloader.hook_in!
        elsif defined?(ActionDispatch::Reloader) # post 0f7c970
          ActionDispatch::Reloader.to_prepare(:prepend => true) { ActiveSupport::Dependencies.unload_modified_files! }
        else
          ActionDispatch::Callbacks.before(:prepend => true)    { ActiveSupport::Dependencies.unload_modified_files! }
        end
        
        DependenciesPatch.enable_async_mode_by_default!
      end
    end
    
    delegate :boost_enabled?, :supports_reload_classes_only_on_change?, :to => 'self.class'
    
    def self.boost_enabled?
      !$rails_rake_task && (Rails.env.development? || (config.respond_to?(:soft_reload) && config.soft_reload))
    end
    
    def self.supports_reload_classes_only_on_change?
      Rails.application.config.respond_to?(:reload_classes_only_on_change)
    end
    
    initializer 'dev_boost.setup', :after => :load_active_support do |app|
      if boost_enabled?
        [DependenciesPatch, ReferencePatch, DescendantsTrackerPatch, ObservablePatch, ReferenceCleanupPatch, LoadablePatch].each(&:apply!)
        
        if defined?(AbstractController::Helpers)
          ViewHelpersPatch.apply!
        else
          ActiveSupport.on_load(:action_controller) { ViewHelpersPatch.apply! }
        end
        
        app.config.middleware.use 'RailsDevelopmentBoost::Async::Middleware'
      end
    end
  end
  
  autoload :Async,                   'rails_development_boost/async'
  autoload :DependenciesPatch,       'rails_development_boost/dependencies_patch'
  autoload :DescendantsTrackerPatch, 'rails_development_boost/descendants_tracker_patch'
  autoload :LoadedFile,              'rails_development_boost/loaded_file'
  autoload :LoadablePatch,           'rails_development_boost/loadable_patch'
  autoload :ObservablePatch,         'rails_development_boost/observable_patch'
  autoload :ReferencePatch,          'rails_development_boost/reference_patch'
  autoload :ReferenceCleanupPatch,   'rails_development_boost/reference_cleanup_patch'
  autoload :Reloader,                'rails_development_boost/reloader'
  autoload :RequiredDependency,      'rails_development_boost/required_dependency'
  autoload :ViewHelpersPatch,        'rails_development_boost/view_helpers_patch'
  
  def self.debug!
    DependenciesPatch.debug!
  end
  
  def self.async=(new_value)
    DependenciesPatch.async = new_value
  end
end

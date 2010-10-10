module RailsDevelopmentBoost
  ActiveSupport.on_load(:after_initialize) do
    ReferencePatch.apply!
    DependenciesPatch.apply!
    DescendantsTrackerPatch.apply!
  end
  
  ActiveSupport.on_load(:action_controller) do
    ActiveSupport.on_load(:after_initialize) do
      ViewHelpersPatch.apply!
      ActionDispatch::Callbacks.to_prepare { ActiveSupport::Dependencies.unload_modified_files! }
    end
  end
  
  autoload :DependenciesPatch,       'rails_development_boost/dependencies_patch'
  autoload :LoadedFile,              'rails_development_boost/loaded_file'
  autoload :ViewHelpersPatch,        'rails_development_boost/view_helpers_patch'
  autoload :DescendantsTrackerPatch, 'rails_development_boost/descendants_tracker_patch'
end

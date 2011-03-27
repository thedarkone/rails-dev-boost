module RailsDevelopmentBoost
  def self.apply!
    Object.class_eval do
      alias_method :singleton_class, :metaclass unless respond_to?(:singleton_class)
    end
    
    [DispatcherPatch, DependenciesPatch, ObservablePatch, ViewHelpersPatch, CachedTemplatesPatch].each &:apply!
  end

  autoload :DispatcherPatch,      'rails_development_boost/dispatcher_patch'
  autoload :DependenciesPatch,    'rails_development_boost/dependencies_patch'
  autoload :LoadedFile,           'rails_development_boost/loaded_file'
  autoload :ObservablePatch,      'rails_development_boost/observable_patch'
  autoload :ViewHelpersPatch,     'rails_development_boost/view_helpers_patch'
  autoload :CachedTemplatesPatch, 'rails_development_boost/cached_templates_patch'
  
  def self.debug!
    DependenciesPatch.debug!
  end
end

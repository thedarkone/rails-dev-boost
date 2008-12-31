module RailsDevelopmentBoost
  def self.apply!
    [DispatcherPatch, DependenciesPatch, ViewHelpersPatch, CachedTemplatesPatch].each &:apply!
  end

  autoload :DispatcherPatch,      'rails_development_boost/dispatcher_patch'
  autoload :DependenciesPatch,    'rails_development_boost/dependencies_patch'
  autoload :LoadedFile,           'rails_development_boost/loaded_file'
  autoload :ViewHelpersPatch,     'rails_development_boost/view_helpers_patch'
  autoload :CachedTemplatesPatch, 'rails_development_boost/cached_templates_patch'
end

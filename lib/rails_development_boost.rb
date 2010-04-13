module RailsDevelopmentBoost
  def self.apply!
    Object.class_eval do
      alias_method :singleton_class, :metaclass unless respond_to?(:singleton_class)
    end
    
    [DispatcherPatch, DependenciesPatch, ViewHelpersPatch].each &:apply!
  end

  autoload :DispatcherPatch,      'rails_development_boost/dispatcher_patch'
  autoload :DependenciesPatch,    'rails_development_boost/dependencies_patch'
  autoload :LoadedFile,           'rails_development_boost/loaded_file'
  autoload :ViewHelpersPatch,     'rails_development_boost/view_helpers_patch'
end

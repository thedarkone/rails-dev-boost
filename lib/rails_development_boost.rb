module RailsDevelopmentBoost
  def self.apply!
    Object.class_eval do
      alias_method :singleton_class, :metaclass unless respond_to?(:singleton_class)
    end
    
    [DispatcherPatch, DependenciesPatch, ObservablePatch, ViewHelpersPatch].each &:apply!
  end

  autoload :DispatcherPatch,      'rails_development_boost/dispatcher_patch'
  autoload :DependenciesPatch,    'rails_development_boost/dependencies_patch'
  autoload :LoadedFile,           'rails_development_boost/loaded_file'
  autoload :ObservablePatch,      'rails_development_boost/observable_patch'
  autoload :RequiredDependency,   'rails_development_boost/required_dependency'
  autoload :ViewHelpersPatch,     'rails_development_boost/view_helpers_patch'
  
  def self.debug!
    DependenciesPatch.debug!
  end
  
  def self.init!
    RailsDevelopmentBoost.apply! if !$rails_rake_task && (Rails.env.development? || config_soft_reload?)
  end
  
  def self.config_soft_reload?
    defined?(config) && config.respond_to?(:soft_reload) && config.soft_reload
  end
end

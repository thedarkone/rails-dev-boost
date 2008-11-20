module SelectiveConstantUnload
  def self.apply!
    [DispatcherPatch, DependenciesPatch].each &:apply!
  end
  
  # Patches
  autoload :DispatcherPatch,    'selective_constant_unload/dispatcher_patch'
  autoload :DependenciesPatch,  'selective_constant_unload/dependencies_patch'
  
  # Support
  autoload :FutureReference,  'selective_constant_unload/future_reference'
  autoload :LoadedFile,       'selective_constant_unload/loaded_file'
end

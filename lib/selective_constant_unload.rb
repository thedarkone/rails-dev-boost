module SelectiveConstantUnload
  def self.apply!
    [DispatcherPatch, DependenciesPatch].each &:apply!
  end

  autoload :DispatcherPatch,    'selective_constant_unload/dispatcher_patch'
  autoload :DependenciesPatch,  'selective_constant_unload/dependencies_patch'
  autoload :LoadedFile,         'selective_constant_unload/loaded_file'
end

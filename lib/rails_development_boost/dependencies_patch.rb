module RailsDevelopmentBoost
  module DependenciesPatch
    module LoadablePatch
      def require_dependency_with_constant_tracking(*args)
        ActiveSupport::Dependencies.required_dependency(args.first)
        # handle plugins such as concerned_with
        require_dependency_without_constant_tracking(*args)
      end
    end
    
    def self.apply!
      # retain the original method in case the application overwrites it on its modules/klasses
      Module.send :alias_method, :_mod_name, :name
      
      patch = self
      ActiveSupport::Dependencies.module_eval do
        remove_method :remove_unloadable_constants!
        alias_method :local_const_defined?, :uninherited_const_defined? unless method_defined?(:local_const_defined?) # pre 4da45060 compatibility
        include patch
        alias_method_chain :load_file, 'constant_tracking'
        alias_method_chain :remove_constant, 'handling_of_connections'
        extend self
      end
      
      ActiveSupport::Dependencies::Loadable.module_eval do
        include LoadablePatch
        alias_method_chain :require_dependency, 'constant_tracking'
      end

      InstrumentationPatch.apply! if @do_instrument
      
      ActiveSupport::Dependencies.handle_already_autoloaded_constants!
    end
  
    def self.debug!
      if ActiveSupport::Dependencies < DependenciesPatch
        InstrumentationPatch.apply!
      else
        @do_instrument = true
      end
    end
    
    autoload :InstrumentationPatch, 'rails_development_boost/dependencies_patch/instrumentation_patch'
  
    mattr_accessor :module_cache
    self.module_cache = []
    
    mattr_accessor :file_map
    self.file_map = {}
    
    mattr_accessor :constants_being_removed
    self.constants_being_removed = []
    
    mattr_accessor :explicit_dependencies
    self.explicit_dependencies = {}
    
    def unload_modified_files
      file_map.values.each do |file|
        unload_modified_file(file) if file.changed?
      end
    end
    
    def remove_explicitely_unloadable_constants!
      explicitly_unloadable_constants.each { |const| remove_constant(const) }
    end
    
    # Overridden.
    def remove_unloadable_constants!
      autoloaded_constants.dup.each { |const| remove_constant(const) }
      remove_explicitely_unloadable_constants!
    end
    
    # Augmented `load_file'.
    def load_file_with_constant_tracking(path, *args, &block)
      result = now_loading(path) { load_file_without_constant_tracking(path, *args, &block) }
      
      unless load_once_path?(path)
        new_constants = autoloaded_constants - file_map.values.map(&:constants).flatten
      
        # Associate newly loaded constants to the file just loaded
        associate_constants_to_file(new_constants, path)
      end

      result
    end
    
    def now_loading(path)
      @currently_loading, old_currently_loading = path, @currently_loading
      yield
    rescue Exception => e
      error_loading_file(@currently_loading, e)
    ensure
      @currently_loading = old_currently_loading
    end
    
    def associate_constants_to_file(constants, file_path)
      # freezing strings before using them as Hash keys is slightly more memory efficient
      constants.map!(&:freeze)
      file_path.freeze
      
      loaded_file_for(file_path).add_constants(constants)
    end
    
    def loaded_file_for(file_path)
      file_map[file_path] ||= LoadedFile.new(file_path)
    end
    
    # Augmented `remove_constant'.
    def remove_constant_with_handling_of_connections(const_name)
      fetch_module_cache do
        prevent_further_removal_of(const_name) do
          unprotected_remove_constant(const_name)
        end
      end
    end
    
    def required_dependency(file_name)
      # Rails uses require_dependency for loading helpers, we are however dealing with the helper problem elsewhere, so we can skip them
      if @currently_loading && @currently_loading !~ /_controller(?:\.rb)?\Z/ && file_name !~ /_helper(?:\.rb)?\Z/
        if full_path = ActiveSupport::Dependencies.search_for_file(file_name)
          loaded_file_for(@currently_loading).associate_with(loaded_file_for(full_path))
        end
      end
    end
    
    def add_explicit_dependency(parent, child)
      (explicit_dependencies[parent._mod_name] ||= []) << child._mod_name
    end
    
    def handle_already_autoloaded_constants! # we might be late to the party and other gems/plugins might have already triggered autoloading of some constants
      loaded.each do |require_path|
        associate_constants_to_file(autoloaded_constants, "#{require_path}.rb") # slightly heavy-handed..
      end
    end
    
  private
    def unprotected_remove_constant(const_name)
      if qualified_const_defined?(const_name) && object = const_name.constantize
        handle_connected_constants(object, const_name)
        remove_same_file_constants(const_name)
        if object.kind_of?(Module)
          remove_parent_modules_if_autoloaded(object)
          remove_child_module_constants(object)
        end
      end
      result = remove_constant_without_handling_of_connections(const_name)
      clear_tracks_of_removed_const(const_name)
      result
    end
  
    def unload_file(file)
      file.constants.dup.each {|const| remove_constant(const)}
      clean_up_if_no_constants(file)
    end
    alias_method :unload_modified_file, :unload_file
    
    def error_loading_file(file_path, e)
      loaded_file_for(file_path).stale!
      raise e
    end
    
    def handle_connected_constants(object, const_name)
      return unless Module === object && qualified_const_defined?(const_name)
      remove_explicit_dependencies_of(const_name)
      remove_dependent_modules(object)
      update_activerecord_related_references(object)
      remove_nested_constants(const_name)
    end
    
    def remove_nested_constants(const_name)
      autoloaded_constants.grep(/\A#{const_name}::/).each { |const| remove_nested_constant(const_name, const) }
    end
    
    def remove_nested_constant(parent_const, child_const)
      remove_constant(child_const)
    end
    
    def autoloaded_namespace_object?(object) # faster than going through Dependencies.autoloaded?
      LoadedFile.constants_to_files[object._mod_name]
    end
    
    # AS::Dependencies doesn't track same-file nested constants, so we need to look out for them on our own.
    # For example having loaded an abc.rb that looks like this:
    #   class Abc; class Inner; end; end
    # AS::Dependencies would only add "Abc" constant name to its autoloaded_constants list, completely ignoring Abc::Inner. This in turn
    # can cause problems for classes inheriting from Abc::Inner somewhere else in the app.
    def remove_parent_modules_if_autoloaded(object)
      unless autoloaded_namespace_object?(object)
        initial_object = object
        
        while (object = object.parent) != Object
          if autoloaded_namespace_object?(object)
            remove_autoloaded_parent_module(initial_object, object)
            break
          end
        end
      end
    end
    
    def remove_autoloaded_parent_module(initial_object, parent_object)
      remove_constant(parent_object._mod_name)
    end
    
    # AS::Dependencies doesn't track same-file nested constants, so we need to look out for them on our own and remove any dependent modules/constants
    def remove_child_module_constants(object)
      object.constants.each do |const_name|
        # we only care about "namespace" constants (classes/modules)
        if local_const_defined?(object, const_name) && (child_const = object.const_get(const_name)).kind_of?(Module)
          remove_child_module_constant(object, child_const)
        end
      end
    end
    
    def remove_child_module_constant(parent_object, child_constant)
      remove_constant(child_constant._mod_name)
    end
    
    def in_autoloaded_namespace?(object)
      while object != Object
        return true if autoloaded_namespace_object?(object)
        object = object.parent
      end
      false
    end    
    
    def remove_same_file_constants(const_name)
      LoadedFile.each_file_with_const(const_name) {|file| unload_containing_file(const_name, file)}
    end
    
    def unload_containing_file(const_name, file)
      unload_file(file)
    end
    
    def remove_explicit_dependencies_of(const_name)
      if dependencies = explicit_dependencies.delete(const_name)
        dependencies.uniq.each {|depending_const| remove_explicit_dependency(const_name, depending_const)}
      end
    end
    
    def remove_explicit_dependency(const_name, depending_const)
      remove_constant(depending_const)
    end
    
    def clear_tracks_of_removed_const(const_name)
      autoloaded_constants.delete(const_name)
      module_cache.delete_if { |mod| mod._mod_name == const_name }
      
      LoadedFile.each_file_with_const(const_name) do |file|
        file.delete_constant(const_name)
        clean_up_if_no_constants(file)
      end
    end
    
    def clean_up_if_no_constants(file)
      if file.constants.empty?
        loaded.delete(file.require_path)
        file_map.delete(file.path)
      end
    end
    
    def remove_dependent_modules(mod)
      fetch_module_cache do |modules|
        modules.dup.each do |other|
          next unless other < mod || other.singleton_class.ancestors.include?(mod)
          next unless first_non_anonymous_superclass(other) == mod if Class === mod
          next unless qualified_const_defined?(other._mod_name) && other._mod_name.constantize == other
          next unless in_autoloaded_namespace?(other)
          remove_dependent_constant(mod, other)
        end
      end
    end
    
    def remove_dependent_constant(original_module, dependent_module)
      remove_constant(dependent_module._mod_name)
    end
    
    def first_non_anonymous_superclass(klass)
      while (klass = klass.superclass) && anonymous?(klass); end
      klass
    end
    
    # egrep -ohR '@\w*([ck]lass|refl|target|own)\w*' activerecord | sort | uniq
    def update_activerecord_related_references(klass)
      return unless defined?(ActiveRecord)
      return unless klass < ActiveRecord::Base

      # Reset references held by macro reflections (klass is lazy loaded, so
      # setting its cache to nil will force the name to be resolved again).
      ActiveRecord::Base.instance_eval { subclasses }.each do |model|
        model.reflections.each_value do |reflection|
          reflection.instance_eval do
            @klass = nil if @klass == klass
          end
        end
      end

      # Update ActiveRecord subclass tree
      registry = ActiveRecord::Base.class_eval("@@subclasses")
      registry.delete(klass)
      (registry[klass.superclass] || []).delete(klass)
    end
    
    def anonymous?(mod)
      !(name = mod._mod_name) || name.empty?
    end
  
  private

    def fetch_module_cache
      return(yield(module_cache)) if module_cache.any?
      
      ObjectSpace.each_object(Module) { |mod| module_cache << mod unless anonymous?(mod) }
      begin
        yield module_cache
      ensure
        module_cache.clear
      end
    end

    def prevent_further_removal_of(const_name)
      return if constants_being_removed.include?(const_name)
      
      constants_being_removed << const_name
      begin
        yield
      ensure
        constants_being_removed.delete(const_name)
      end
    end
  end
end

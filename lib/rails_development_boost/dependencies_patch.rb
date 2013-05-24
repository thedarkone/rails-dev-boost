require 'active_support/dependencies'

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
      return if applied?
      
      # retain the original method in case the application overwrites it on its modules/klasses
      Module.send :alias_method, :_mod_name, :name
      
      patch = self
      ActiveSupport::Dependencies.module_eval do
        alias_method :local_const_defined?, :uninherited_const_defined? unless method_defined?(:local_const_defined?) # pre 4da45060 compatibility
        remove_possible_method :remove_unloadable_constants!
        remove_possible_method :clear
        include patch
        alias_method_chain :load_file, 'constant_tracking'
        alias_method_chain :remove_constant, 'handling_of_connections'
        extend patch
      end
      
      ActiveSupport::Dependencies::Loadable.module_eval do
        include LoadablePatch
        alias_method_chain :require_dependency, 'constant_tracking'
      end

      InstrumentationPatch.apply! if @do_instrument
      
      ActiveSupport::Dependencies.handle_already_autoloaded_constants!
    end
  
    def self.debug!
      if applied?
        InstrumentationPatch.apply!
      else
        @do_instrument = true
      end
    end
    
    def self.async=(new_value)
      @async = Async.process_new_async_value(new_value)
    end
    
    def self.async?
      @async
    end
    
    def self.enable_async_mode_by_default!
      Async.enable_by_default!(defined?(@async))
    end
    
    def self.applied?
      ActiveSupport::Dependencies < self
    end
    
    autoload :InstrumentationPatch, 'rails_development_boost/dependencies_patch/instrumentation_patch'
  
    mattr_accessor :constants_being_removed
    self.constants_being_removed = []
    
    mattr_accessor :explicit_dependencies
    self.explicit_dependencies = {}
    
    mattr_accessor :currently_loading
    self.currently_loading = []
    
    module Util
      extend self
      
      def anonymous_const?(mod)
        anonymous_const_name?(mod._mod_name)
      end
      
      def anonymous_const_name?(const_name)
        !const_name || const_name.empty?
      end
      
      def first_non_anonymous_superclass(klass)
        while (klass = klass.superclass) && anonymous_const?(klass); end
        klass
      end
      
      NOTHING = ''
      def in_autoloaded_namespace?(const_name) # careful, modifies passed in const_name!
        begin
          return true if LoadedFile.loaded_constant?(const_name)
        end while const_name.sub!(/::[^:]+\Z/, NOTHING)
        false
      end
    end
    
    class ModuleCache
      def initialize
        @classes, @modules = [], []
        ObjectSpace.each_object(Module) {|mod| self << mod if relevant?(mod)}
        @singleton_ancestors = Hash.new {|h, klass| h[klass] = klass.singleton_class.ancestors}
      end
      
      def each_dependent_on(mod, &block)
        arr = []
        each_inheriting_from(mod) do |other|
          mod_name = other._mod_name
          arr << other if qualified_const_defined?(mod_name) && mod_name.constantize == other
        end
        arr.each(&block)
      end
      
      def remove_const(const_name, object)
        if object && Class === object
          remove_const_from_colletion(@classes, const_name, object)
        else
          [@classes, @modules].each {|collection| remove_const_from_colletion(collection, const_name, object)}
        end
      end
      
      def <<(mod)
        (Class === mod ? @classes : @modules) << mod
      end
      
      private
      def relevant?(mod)
        const_name = mod._mod_name
        !Util.anonymous_const_name?(const_name) && Util.in_autoloaded_namespace?(const_name)
      end
      
      def remove_const_from_colletion(collection, const_name, object)
        if object
          collection.delete(object)
        else
          collection.delete_if {|mod| mod._mod_name == const_name}
        end
      end
      
      def each_inheriting_from(mod_or_class)
        if Class === mod_or_class
          @classes.each do |other_class|
            yield other_class if other_class < mod_or_class && Util.first_non_anonymous_superclass(other_class) == mod_or_class
          end
        else
          [@classes, @modules].each do |collection|
            collection.each do |other|
              yield other if other < mod_or_class || @singleton_ancestors[other].include?(mod_or_class)
            end
          end
        end
      end
      
      def qualified_const_defined?(const_name)
        ActiveSupport::Dependencies.qualified_const_defined?(const_name)
      end
    end
    
    def unload_modified_files!
      async_synchronize do
        begin
          unloaded_something = unload_modified_files_internal!
          load_failure       = clear_load_failure
          unloaded_something || load_failure
        ensure
          @module_cache = nil
        end
      end
    end
    
    def remove_explicitely_unloadable_constants!
      explicitly_unloadable_constants.each { |const| remove_constant(const) }
    end
    
    # Overridden.
    def clear
    end
    
    # Augmented `load_file'.
    def load_file_with_constant_tracking(path, *args)
      async_synchronize do
        @module_cache = nil # nuking the module_cache helps to avoid any stale-class issues when the async mode is used in a console session
        load_file_with_constant_tracking_internal(path, args)
      end
    end
    
    def now_loading(path)
      currently_loading << path
      yield
    rescue Exception => e
      error_loading_file(currently_loading.last, e)
    ensure
      currently_loading.pop
    end
    
    def associate_constants_to_file(constants, file_path)
      # freezing strings before using them as Hash keys is slightly more memory efficient
      constants.map!(&:freeze)
      file_path.freeze
      
      LoadedFile.for(file_path).add_constants(constants)
    end
    
    # Augmented `remove_constant'.
    def remove_constant_with_handling_of_connections(const_name)
      async_synchronize do
        module_cache # make sure module_cache has been created
        prevent_further_removal_of(const_name) do
          unprotected_remove_constant(const_name)
        end
      end
    end
    
    def required_dependency(file_name)
      # Rails uses require_dependency for loading helpers, we are however dealing with the helper problem elsewhere, so we can skip them
      return if (curr_loading = currently_loading.last) && curr_loading =~ /_controller(?:\.rb)?\Z/ && file_name =~ /_helper(?:\.rb)?\Z/
      
      if full_path = ActiveSupport::Dependencies.search_for_file(file_name)
        RequiredDependency.new(curr_loading).related_files.each do |related_file|
          LoadedFile.relate_files(related_file, full_path)
        end
      end
    end
    
    def add_explicit_dependency(parent, child)
      if !Util.anonymous_const_name?(child_mod_name = child._mod_name) && !Util.anonymous_const_name?(parent_mod_name = parent._mod_name)
        ((explicit_dependencies[parent_mod_name] ||= []) << child_mod_name).uniq!
      end
    end
    
    def handle_already_autoloaded_constants! # we might be late to the party and other gems/plugins might have already triggered autoloading of some constants
      loaded.each do |require_path|
        unless load_once_path?(require_path)
          associate_constants_to_file(autoloaded_constants, "#{require_path}.rb") # slightly heavy-handed..
        end
      end
    end
    
    def in_autoload_path?(expanded_file_path)
      autoload_paths.any? do |autoload_path|
        autoload_path = autoload_path.to_s # handle Pathnames
        expanded_file_path.starts_with?(autoload_path.ends_with?('/') ? autoload_path : "#{autoload_path}/")
      end
    end
    
    def load_file_from_explicit_load(expanded_path)
      unless LoadedFile.loaded?(expanded_path)
        load_file(expanded_path)
        if LoadedFile.loaded?(expanded_path) && (file = LoadedFile.for(expanded_path)).decorator_like?
          file.associate_to_greppable_constants
        end
      end
    end
    
  private
    def unload_modified_files_internal!
      log_call
      if DependenciesPatch.async?
        # because of the forking ruby servers (threads don't survive the forking),
        # the Async heartbeat/init check needs to be here (instead of it being a boot time thing)
        Async.heartbeat_check!
      else
        LoadedFile.unload_modified!
      end
    end
  
    def clear_load_failure
      @load_failure.tap { @load_failure = false }
    end

    def load_file_with_constant_tracking_internal(path, args)
      result = now_loading(path) { load_file_without_constant_tracking(path, *args) }
      
      unless load_once_path?(path)
        new_constants = autoloaded_constants - LoadedFile.loaded_constants
      
        # Associate newly loaded constants to the file just loaded
        associate_constants_to_file(new_constants, path)
      end

      result
    end
  
    def async_synchronize
      if DependenciesPatch.async?
        Async.synchronize { yield }
      else
        yield
      end
    end
  
    def unprotected_remove_constant(const_name)
      if qualified_const_defined?(const_name) && object = const_name.constantize
        handle_connected_constants(object, const_name)
        LoadedFile.unload_files_with_const!(const_name)
        if object.kind_of?(Module)
          remove_parent_modules_if_autoloaded(object)
          remove_child_module_constants(object, const_name)
        end
      end
      result = remove_constant_without_handling_of_connections(const_name)
      clear_tracks_of_removed_const(const_name, object)
      result
    end
  
    def error_loading_file(file_path, e)
      LoadedFile.for(file_path).stale! if LoadedFile.loaded?(file_path)
      @load_failure = true
      raise e
    end
    
    def handle_connected_constants(object, const_name)
      return unless Module === object && qualified_const_defined?(const_name)
      remove_explicit_dependencies_of(const_name)
      remove_dependent_modules(object)
      update_activerecord_related_references(object)
      update_mongoid_related_references(object)
      remove_nested_constants(const_name)
    end
    
    def remove_nested_constants(const_name)
      autoloaded_constants.grep(/\A#{const_name}::/) { |const| remove_nested_constant(const_name, const) }
    end
    
    def remove_nested_constant(parent_const, child_const)
      remove_constant(child_const)
    end
    
    # AS::Dependencies doesn't track same-file nested constants, so we need to look out for them on our own.
    # For example having loaded an abc.rb that looks like this:
    #   class Abc; class Inner; end; end
    # AS::Dependencies would only add "Abc" constant name to its autoloaded_constants list, completely ignoring Abc::Inner. This in turn
    # can cause problems for classes inheriting from Abc::Inner somewhere else in the app.
    def remove_parent_modules_if_autoloaded(object)
      unless autoloaded_object?(object)
        initial_object = object
        
        while (object = object.parent) != Object
          if autoloaded_object?(object)
            remove_autoloaded_parent_module(initial_object, object)
            break
          end
        end
      end
    end
    
    def remove_autoloaded_parent_module(initial_object, parent_object)
      remove_constant(parent_object._mod_name)
    end
    
    def autoloaded_object?(object) # faster than going through Dependencies.autoloaded?
      LoadedFile.loaded_constant?(object._mod_name)
    end
    
    # AS::Dependencies doesn't track same-file nested constants, so we need to look out for them on our own and remove any dependent modules/constants
    def remove_child_module_constants(object, object_const_name)
      object.constants.each do |child_const_name|
        # we only care about "namespace" constants (classes/modules)
        if (child_const = get_child_const(object, child_const_name)).kind_of?(Module)
          # make sure this is not "const alias" created like this: module Y; end; module A; X = Y; end, const A::X is not a proper "namespacing module",
          # but only an alias to Y module
          if (full_child_const_name = child_const._mod_name) == "#{object_const_name}::#{child_const_name}"
            remove_child_module_constant(object, full_child_const_name)
          end
        end
      end
    end
    
    def get_child_const(object, child_const_name)
      if local_const_defined?(object, child_const_name)
        begin
          object.const_get(child_const_name)
        rescue NameError
          # Apparently even though we get a list of constants through the native Module#constants and do a local_const_defined? check the const_get
          # can still fail with a NameError (const undefined etc.)
          # See https://github.com/thedarkone/rails-dev-boost/pull/33 for more details.
        end
      end
    end
    
    def remove_child_module_constant(parent_object, full_child_const_name)
      remove_constant(full_child_const_name)
    end
    
    def remove_explicit_dependencies_of(const_name)
      if dependencies = explicit_dependencies.delete(const_name)
        dependencies.each do |depending_const|
          remove_explicit_dependency(const_name, depending_const) if LoadedFile.loaded_constant?(depending_const)
        end
      end
    end
    
    def remove_explicit_dependency(const_name, depending_const)
      remove_constant(depending_const)
    end
    
    def clear_tracks_of_removed_const(const_name, object = nil)
      autoloaded_constants.delete(const_name)
      module_cache.remove_const(const_name, object)
      LoadedFile.const_unloaded(const_name)
    end
    
    def remove_dependent_modules(mod)
      module_cache.each_dependent_on(mod) {|other| remove_dependent_constant(mod, other)}
    end
    
    def remove_dependent_constant(original_module, dependent_module)
      remove_constant(dependent_module._mod_name)
    end
    
    AR_REFLECTION_CACHES = [:@klass]
    # egrep -ohR '@\w*([ck]lass|refl|target|own)\w*' activerecord | sort | uniq
    def update_activerecord_related_references(klass)
      return unless defined?(ActiveRecord)
      return unless klass < ActiveRecord::Base

      # Reset references held by macro reflections (klass is lazy loaded, so
      # setting its cache to nil will force the name to be resolved again).
      ActiveRecord::Base.descendants.each do |model|
        clean_up_relation_caches(model.reflections, klass, AR_REFLECTION_CACHES)
      end
    end
    
    MONGOID_RELATION_CACHES = [:@klass, :@inverse_klass]
    def update_mongoid_related_references(klass)
      if defined?(Mongoid::Document) && klass < Mongoid::Document
        while (superclass = Util.first_non_anonymous_superclass(superclass || klass)) != Object && superclass < Mongoid::Document
          remove_constant(superclass._mod_name) # this is necessary to nuke the @_types caches
        end
        
        module_cache.each_dependent_on(Mongoid::Document) do |model|
          clean_up_relation_caches(model.relations, klass, MONGOID_RELATION_CACHES)
        end
      end
    end
    
    def clean_up_relation_caches(relations, klass, ivar_names)
      relations.each_value do |relation|
        ivar_names.each do |ivar_name|
          relation.instance_variable_set(ivar_name, nil) if relation.instance_variable_get(ivar_name) == klass
        end
      end
    end
    
    def module_cache
      @module_cache ||= ModuleCache.new
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

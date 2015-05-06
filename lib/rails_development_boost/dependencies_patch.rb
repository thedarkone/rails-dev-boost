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
        unless method_defined?(:local_const_defined?) # pre 4da45060 compatibility
          if method_defined?(:uninherited_const_defined?)
            alias_method :local_const_defined?, :uninherited_const_defined?
          else # post 4.0 compat
            def local_const_defined?(mod, const_name)
              mod.const_defined?(const_name, false)
            end
          end
        end
        remove_possible_method :remove_unloadable_constants!
        remove_possible_method :clear
        include patch
        alias_method_chain :load_file, 'constant_tracking'
        alias_method_chain :remove_constant, 'handling_of_connections'
        extend patch
        @routes_path_loading = nil
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
      
      def load_path_to_real_path(path)
        expanded_path = File.expand_path(path)
        expanded_path << '.rb' unless expanded_path =~ /\.r(?:b|ake)\Z/
        expanded_path
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
    
    class ConstantsHeap < Array
      NAMESPACE_SEPARATOR = '::'
      
      def initialize(*args)
        super
        @seen = Set.new
      end
      
      def add_const?(const_name, force_insert = false)
        if @seen.add?(const_name) || force_insert
          (self[const_name.count(NAMESPACE_SEPARATOR)] ||= []) << const_name
          true
        else
          false
        end
      end
      
      def pop_next_const
        reverse_each do |slot|
          if const_name = slot.try(:pop)
            return const_name
          end
        end
        nil
      end
      
      def seen?(const_name)
        @seen.include?(const_name)
      end
      
      def clear_seen
        @seen.clear
      end
    end
    
    mattr_accessor :constants_to_remove
    self.constants_to_remove = ConstantsHeap.new
    
    def unload_modified_files!
      async_synchronize do
        unloaded_something = unload_modified_files_internal!
        load_failure       = clear_load_failure
        unloaded_something || load_failure
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
        if @module_cache
          @module_cache = nil
          constants_to_remove.clear_seen
        end
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
    
    def loading_routes_file(path)
      prev_value = @routes_path_loading
      @routes_path_loading = Util.load_path_to_real_path(path)
      yield
    ensure
      @routes_path_loading = prev_value
    end
    
    def associate_constants_to_file(constants, file_path)
      # freezing strings before using them as Hash keys is slightly more memory efficient
      constants.map!(&:freeze)
      file_path.freeze
      
      LoadedFile.for(file_path).add_constants(constants)
    end
    
    def schedule_const_for_unloading(const_name)
      if constants_to_remove.add_const?(const_name)
        if qualified_const_defined?(const_name) && object = const_name.constantize
          @module_cache ||= ModuleCache.new # make sure module_cache has been created
          schedule_dependent_constants_for_removal(const_name, object)
        end
        true
      end
    end
    
    def process_consts_scheduled_for_removal
      unless @now_removing_const
        @now_removing_const = true
        begin
          process_consts_scheduled_for_removal_internal
        ensure
          @now_removing_const = nil
        end
      end
    end
    
    # Augmented `remove_constant'.
    def remove_constant_with_handling_of_connections(const_name)
      async_synchronize do
        schedule_const_for_unloading(const_name)
        process_consts_scheduled_for_removal
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
      # puts "handle_already_autoloaded_constants!: #{loaded.inspect}"
      # fake_routes_file = RoutesLoadedFile.for('fake_routes_file')
      each_loaded_rb_file_path do |loaded_rb_file_path|
        associate_constants_to_file(autoloaded_constants, loaded_rb_file_path) # slightly heavy-handed, because afterwards it is impossible to tell which file contained which constant
      end
    end
    
    # This attempts to fix a problem of autoloaded constants being directly referenced by Rails routes, ie: `mount Twitter::API => '/twitter-api'` (where Twitter::API is Rails autoloaded).
    # The problem is compounded during Rails initialization, if a code (for example in an initializer) loads an autoloaded constant and subsequently routes are evaluated. Normally rails-dev-boost
    # tries to detect a routes -> const dependency by the fact that during a routes evaluation a new constant autoloading is triggered, but if it already exists (because of an initializer)
    # this link is broken.
    def associate_all_loaded_consts_to_routes!
      fake_routes_file = RoutesLoadedFile.for('fake_routes_file') # doesn't actually have to point to a real .rb file
      each_loaded_rb_file_path do |loaded_rb_file_path|
        fake_routes_file.associate_with(LoadedFile.for(loaded_rb_file_path))
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
    def each_loaded_rb_file_path
      loaded.each do |require_path|
        yield "#{require_path}.rb" unless load_once_path?(require_path)
      end
    end
    
    def process_consts_scheduled_for_removal_internal
      heap   = constants_to_remove
      result = nil
      while const_to_remove = heap.pop_next_const
        begin
          result = unprotected_remove_constant(const_to_remove, qualified_const_defined?(const_to_remove) && const_to_remove.constantize)
        rescue Exception
          heap.add_const?(const_to_remove, true)
          raise
        end
      end
      result
    end
  
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
        if routes_path_loading = @routes_path_loading
          RoutesLoadedFile.for(routes_path_loading).associate_with(LoadedFile.for(path))
        end
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
    
    def schedule_dependent_constants_for_removal(const_name, object)
      handle_connected_constants(object, const_name)
      LoadedFile.schedule_for_unloading_files_with_const!(const_name)
      if object.kind_of?(Module)
        remove_parent_modules_if_autoloaded(object)
        remove_child_module_constants(object, const_name)
      end
    end
  
    def unprotected_remove_constant(const_name, object)
      result = remove_constant_without_handling_of_connections(const_name)
      clear_tracks_of_removed_const(const_name, object)
      result
    end
  
    def error_loading_file(file_path, e)
      LoadedFile.for(file_path).stale! if LoadedFile.loaded?(file_path)
      # only the errors that blow through the full stack are load failures, this lets user code handle failed load failures by rescuing raised exceptions without triggering a full dependecies reload
      @load_failure = true if currently_loading.size == 1
      raise e
    end
    
    def handle_connected_constants(object, const_name)
      return unless Module === object && qualified_const_defined?(const_name)
      remove_nested_constants(const_name)
      remove_explicit_dependencies_of(const_name)
      remove_dependent_modules(object)
      # TODO move these into the cleanup phase
      clean_up_references(object)
    end
    
    def remove_nested_constants(const_name)
      autoloaded_constants.grep(/\A#{const_name}::/) { |const| remove_nested_constant(const_name, const) }
    end
    
    def remove_nested_constant(parent_const, child_const)
      schedule_const_for_unloading(child_const)
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
      schedule_const_for_unloading(parent_object._mod_name)
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
      schedule_const_for_unloading(full_child_const_name)
    end
    
    def remove_explicit_dependencies_of(const_name)
      if dependencies = explicit_dependencies.delete(const_name)
        dependencies.each do |depending_const|
          remove_explicit_dependency(const_name, depending_const) if LoadedFile.loaded_constant?(depending_const)
        end
      end
    end
    
    def remove_explicit_dependency(const_name, depending_const)
      schedule_const_for_unloading(depending_const)
    end
    
    def clear_tracks_of_removed_const(const_name, object = nil)
      autoloaded_constants.delete(const_name)
      # @module_cache might be nil if remove_constant has been called with a non-existent constant, ie: it hasn't been checked with `qualified_const_defined?`. Because AS::Dep doesn't blow, neither
      # should we.
      @module_cache.remove_const(const_name, object) if @module_cache
      LoadedFile.const_unloaded(const_name)
    end
    
    def remove_dependent_modules(mod)
      @module_cache.each_dependent_on(mod) {|other| remove_dependent_constant(mod, other)}
    end
    
    def remove_dependent_constant(original_module, dependent_module)
      schedule_const_for_unloading(dependent_module._mod_name)
    end
    
    def clean_up_references(object)
      clean_up_methods = []
      clean_up_methods << :update_activerecord_related_references if defined?(ActiveRecord)
      clean_up_methods << :update_mongoid_related_references      if defined?(Mongoid::Document)
      clean_up_methods << :update_authlogic_related_references    if defined?(Authlogic::Session::Base)
      
      # compile the clean-up method names to avoid the constant defined? check overhead
      RailsDevelopmentBoost::DependenciesPatch.class_eval <<-RUBY_EVAL, __FILE__, __LINE__
        def clean_up_references(object)
          #{clean_up_methods.map {|clean_up_method| "#{clean_up_method}(object)"}.join(';')}
        end
      RUBY_EVAL
      
      clean_up_methods.each {|clean_up_method| send(clean_up_method, object)}
    end
    
    AR_REFLECTION_CACHES = [:@klass]
    # egrep -ohR '@\w*([ck]lass|refl|target|own)\w*' activerecord | sort | uniq
    def update_activerecord_related_references(klass)
      return unless klass < ActiveRecord::Base

      # Reset references held by macro reflections (klass is lazy loaded, so
      # setting its cache to nil will force the name to be resolved again).
      ActiveRecord::Base.descendants.each do |model|
        clean_up_relation_caches(model.reflections, klass, AR_REFLECTION_CACHES)
      end
    end
    
    MONGOID_RELATION_CACHES = [:@klass, :@inverse_klass]
    def update_mongoid_related_references(klass)
      if klass < Mongoid::Document
        while (superclass = Util.first_non_anonymous_superclass(superclass || klass)) != Object && superclass < Mongoid::Document
          schedule_const_for_unloading(superclass._mod_name) # this is necessary to nuke the @_types caches
        end
        
        @module_cache.each_dependent_on(Mongoid::Document) do |model|
          clean_up_relation_caches(model.relations, klass, MONGOID_RELATION_CACHES)
        end
      end
    end
    
    def update_authlogic_related_references(klass)
      Authlogic::Session::Base.descendants.each do |descendant|
        # opting for remove_dependent_constant instead of niling @klass because Authlogic allows users to set the klass themselves (via authenticate_with)
        remove_dependent_constant(klass, descendant) if klass == descendant.instance_variable_get(:@klass)
      end
    end
    
    def clean_up_relation_caches(relations, klass, ivar_names)
      relations.each_value do |relation|
        ivar_names.each do |ivar_name|
          relation.instance_variable_set(ivar_name, nil) if relation.instance_variable_get(ivar_name) == klass
        end
      end
    end
  end
end

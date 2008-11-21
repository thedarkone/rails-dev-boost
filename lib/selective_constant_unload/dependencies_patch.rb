module SelectiveConstantUnload
  module DependenciesPatch
    def self.apply!
      patch = self
      ActiveSupport::Dependencies.module_eval do
        include patch
        remove_method :remove_unloadable_constants!
        alias_method_chain :load_file, 'constant_tracking'
        alias_method_chain :remove_constant, 'treatment_of_connections'
        extend self
      end
    end
    
    mattr_accessor :file_map
    self.file_map = {}
    
    # Overridden.
    def remove_unloadable_constants!
      #autoloaded_constants.each { |const| remove_constant const }
      #autoloaded_constants.clear
      explicitly_unloadable_constants.each { |const| remove_constant const }
    end
    
    def unload_modified_files
      file_map.each_value do |file|
        file.constants.each { |const| remove_constant(const) } if file.changed?
      end
    end
    
    # Augmented `load_file'.
    def load_file_with_constant_tracking(path, *args, &block)
      result = load_file_without_constant_tracking(path, *args, &block)
      new_constants = autoloaded_constants - file_map.values.map(&:constants).flatten
      
      # Associate newly loaded constants to the file just loaded
      if new_constants.any?
        path_marked_loaded = path.sub('.rb', '')
        file_map[path_marked_loaded] ||= LoadedFile.new(path)
        file_map[path_marked_loaded].constants |= new_constants
      end

      return result
    end
    
    # Augmented `remove_constant'.
    def remove_constant_with_treatment_of_connections(const_name)
      object = const_name.constantize rescue nil
      treat_connected_constants(object, const_name)
      result = remove_constant_without_treatment_of_connections(const_name)
      remove_tracks_of_unloaded_const(const_name)
      return result
    end
    
  private
    
    def remove_tracks_of_unloaded_const(const)
      autoloaded_constants.delete(const)
      file_map.each do |path, file|
        file.constants.delete(const)
        if file.constants.empty?
          loaded.delete(path)
          file_map.delete(path)
        end
      end
    end
    
    def treat_connected_constants(object, const_name)
      return unless Class === object && qualified_const_defined?(const_name)
      remove_direct_subclasses(object)
      update_activerecord_related_references(object, const_name)
      autoloaded_constants.grep(/^#{const_name}::[^:]+$/).each { |const| remove_constant(const) }
    end
    
    def remove_direct_subclasses(klass)
      Object.subclasses_of(klass).
        select { |subclass| subclass.superclass == klass }.
        each { |subclass| remove_constant(subclass) }
    end
    
    # egrep -ohR '@\w*([ck]lass|refl|target|own)\w*' activerecord | sort | uniq
    def update_activerecord_related_references(object, const_name)
      return unless object < ActiveRecord::Base

      # Reset references held by macro reflections (klass is lazy loaded, so
      # setting its cache to nil will force the name to be resolved again).
      ActiveRecord::Base.instance_eval { subclasses }.each do |model|
        model.reflections.each_value do |reflection|
          reflection.instance_eval do
            @klass = nil if @klass == object
          end
        end
      end

      # Update ActiveRecord's registry of its subclasses
      registry = ActiveRecord::Base.class_eval("@@subclasses")
      registry.delete(object)
      (registry[object.superclass] || []).delete(object)
    end
  end
end

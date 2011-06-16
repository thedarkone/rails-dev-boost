module RailsDevelopmentBoost
  class LoadedFile
    class Files < Hash
      def initialize(*args)
        super {|hash, file_path| hash[file_path] = LoadedFile.new(file_path)}
      end
      
      def unload_modified!
        values.each do |file|
          unload_modified_file(file) if file.changed?
        end
      end
      
      def unload_modified_file(file)
        file.unload!
      end
      
      def constants
        values.map(&:constants).flatten
      end
      
      def stored?(file)
        key?(file.path) && self[file.path] == file
      end
      
      alias_method :loaded?, :key?
    end
    
    class ConstantsToFiles < Hash
      def associate(const_name, file)
        (self[const_name] ||= []) << file
      end
      
      def deassociate(const_name, file)
        if files = self[const_name]
          files.delete(file)
          delete(const_name) if files.empty?
        end
      end
      
      def each_file_with_const(const_name, &block)
        if files = self[const_name]
          files.dup.each(&block)
        end
      end
    end
    
    class Interdependencies < Hash
      def associate(file_a, file_b)
        (self[file_a] ||= []) << file_b
        (self[file_b] ||= []) << file_a
      end
      
      def each_dependent_on(file)
        if deps = delete(file)
          deps.each do |dep|
            deassociate(dep, file)
            yield dep
          end
        end
      end
      
      private
      def deassociate(file_a, file_b)
        if deps = self[file_a]
          deps.delete(file_b)
          delete(file_a) if deps.empty?
        end
      end
    end
    
    LOADED             = Files.new
    CONSTANTS_TO_FILES = ConstantsToFiles.new
    INTERDEPENDENCIES  = Interdependencies.new
    NOW_UNLOADING      = Set.new
    
    attr_accessor :path, :constants
  
    def initialize(path, constants=[])
      @path       = path
      @constants  = constants
      @mtime      = current_mtime
    end
  
    def changed?
      previous_mtime, @mtime = @mtime, current_mtime
      previous_mtime != @mtime
    end
    
    def add_constants(new_constants)
      new_constants.each {|new_constant| CONSTANTS_TO_FILES.associate(new_constant, self)}
      @constants |= new_constants
    end
    
    def unload!
      guard_double_unloading do
        INTERDEPENDENCIES.each_dependent_on(self) {|dependent_file| unload_dependent_file(dependent_file)}
        @constants.dup.each {|const| ActiveSupport::Dependencies.remove_constant(const)}
        clean_up_if_necessary
      end
    end
    
    # consistent hashing
    def hash
      @path.hash
    end
    
    def eql?(other)
      @path.eql?(other)
    end
    
    def unload_dependent_file(dependent_file)
      dependent_file.unload!
    end
    
    def guard_double_unloading
      unless NOW_UNLOADING.include?(self)
        NOW_UNLOADING << self
        begin
          yield
        ensure
          NOW_UNLOADING.delete(self)
        end
      end
    end
    
    def delete_constant(const_name)
      CONSTANTS_TO_FILES.deassociate(const_name, self)
      @constants.delete(const_name)
      clean_up_if_necessary
    end
    
    def clean_up_if_necessary
      if @constants.empty? && LOADED.stored?(self)
        LOADED.delete(@path)
        ActiveSupport::Dependencies.loaded.delete(require_path)
      end
    end
    
    def associate_with(other_loaded_file)
      INTERDEPENDENCIES.associate(self, other_loaded_file)
    end
    
    def require_path
      File.expand_path(@path.sub(/\.rb\Z/, '')) # be sure to do the same thing as Dependencies#require_or_load and use the expanded path
    end
    
    def stale!
      @mtime = 0
      INTERDEPENDENCIES.each_dependent_on(self, &:stale!)
    end
    
    class << self
      def unload_modified!
        LOADED.unload_modified!
      end
      
      def for(file_path)
        LOADED[file_path]
      end
      
      def loaded?(file_path)
        LOADED.loaded?(file_path)
      end
      
      def loaded_constants
        LOADED.constants
      end
      
      def loaded_constant?(const_name)
        CONSTANTS_TO_FILES[const_name]
      end
      
      def unload_files_with_const!(const_name)
        CONSTANTS_TO_FILES.each_file_with_const(const_name) {|file| unload_containing_file(const_name, file)}
      end
      
      def unload_containing_file(const_name, file)
        file.unload!
      end
      
      def const_unloaded(const_name)
        CONSTANTS_TO_FILES.each_file_with_const(const_name) {|file| file.delete_constant(const_name)}
      end
      
      def relate_files(base_file, related_file)
        LOADED[base_file].associate_with(LOADED[related_file])
      end
    end
    
  private
    def current_mtime
      # trying to be more efficient: there is no need for a full-fledged Time instance, just grab the timestamp
      File.mtime(@path).to_i rescue nil
    end
  end
end

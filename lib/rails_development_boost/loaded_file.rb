require 'set'

module RailsDevelopmentBoost
  class LoadedFile
    class Files < Hash
      def initialize(*args)
        @directories = {}
        super {|hash, file_path| hash[file_path] = LoadedFile.new(file_path)}
      end
      
      def []=(file_path, loaded_file)
        (@directories[loaded_file.dirname] ||= Set.new) << loaded_file
        super
      end
      
      def delete(file_path)
        if loaded_file = super
          dirname = loaded_file.dirname
          if @directories[dirname].delete(loaded_file).empty?
            @directories.delete(dirname)
          end
        end
        loaded_file
      end
      
      def unload_modified!(filter_directories = nil)
        unloaded_something = false
        find_files_in(filter_directories).each do |file|
          if file.changed?
            unload_modified_file(file)
            unloaded_something = true
          end
        end
        if unloaded_something
          values.each do |file|
            unload_decorator_file(file) if file.decorator_like?
          end
        end
        unloaded_something
      end
      
      def find_files_in(filter_directories = nil)
        if filter_directories
          arr = []
          @directories.each_pair do |dirname, files|
            arr.concat(files.to_a) if filter_directories.any? {|filter_directory| dirname.starts_with?(filter_directory)}
          end
          arr
        else
          values
        end
      end
      
      def unload_modified_file(file)
        file.unload!
      end
      
      def unload_decorator_file(file)
        file.unload!
      end
      
      def constants
        arr = []
        each_value {|file| arr.concat(file.constants)}
        arr
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
        (self[file_a] ||= Set.new) << file_b
        (self[file_b] ||= Set.new) << file_a
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
    
    def dirname
      File.dirname(@path)
    end
    
    # "decorator" files are popular with certain Rails frameworks (spree/refinerycms etc.) they don't define their own constants, instead
    # they are usually used for adding methods to other classes via Model.class_eval { def meth; end }
    def decorator_like?
      @constants.empty? && !INTERDEPENDENCIES[self]
    end
    
    def unload!
      guard_double_unloading do
        INTERDEPENDENCIES.each_dependent_on(self) {|dependent_file| unload_dependent_file(dependent_file)}
        @constants.dup.each {|const| ActiveSupport::Dependencies.remove_constant(const)}
        clean_up_if_necessary
      end
    end
    
    def associate_to_greppable_constants # brute-force approach
      # we don't know anything about the constants contained in the files up the currently_loading stack
      ActiveSupport::Dependencies.currently_loading.each {|path| self.class.relate_files(path, self)}
      add_constants(greppable_constants)
    end
    
    # It is important to catch all the intermediate constants as they might be "nested" constants, that are generally not tracked by AS::Dependencies.
    # Pathological example is as follows:
    #
    # File `a.rb` contains `class A; X = :x; end`. AS::Dependencies only associates the 'A' const to the `a.rb` file (ignoring the nested 'A::X'), while
    # a decorator file `b_decorator.rb` containing `B.class_eval {A::X}` would grep and find the `A::X` const, check that indeed it is in autoloaded
    # namespace and associate it to itself. When `b_decorator.rb` is then being unloaded it simply does `remove_constant('A::X')` while failing to trigger
    # the unloading of `a.rb`.
    def greppable_constants
      constants = []
      read_greppable_constants.each do |const_name|
        intermediates = nil
        begin
          if self.class.loaded_constant?(const_name)
            constants << const_name
            constants.concat(intermediates) if intermediates
            break
          end
          (intermediates ||= []) << const_name.dup
        end while const_name.sub!(/::[^:]+\Z/, '')
      end
      constants.uniq
    end
    
    def read_greppable_constants
      File.read(@path).scan(/[A-Z][_A-Za-z0-9]*(?:::[A-Z][_A-Za-z0-9]*)*/).uniq
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
      if NOW_UNLOADING.add?(self)
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

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
    
    LOADED             = Files.new
    CONSTANTS_TO_FILES = ConstantsToFiles.new
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
      retrieve_associated_files.each {|file| file.add_constants(@constants)} if @associated_files
    end
    
    def unload!
      guard_double_unloading do
        @constants.dup.each {|const| ActiveSupport::Dependencies.remove_constant(const)}
        clean_up_if_necessary
      end
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
      (@associated_files ||= []) << other_loaded_file
    end
    
    def retrieve_associated_files
      associated_files, @associated_files = @associated_files, nil
      associated_files
    end
    
    def require_path
      File.expand_path(@path.sub(/\.rb\Z/, '')) # be sure to do the same thing as Dependencies#require_or_load and use the expanded path
    end
    
    def stale!
      @mtime = 0
      if associated_files = retrieve_associated_files
        associated_files.each(&:stale!)
      end
    end
    
    class << self
      def unload_modified!
        LOADED.unload_modified!
      end
      
      def for(file_path)
        LOADED[file_path]
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

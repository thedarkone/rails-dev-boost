module RailsDevelopmentBoost
  class LoadedFile
    @constants_to_files = {}
    
    class << self
      attr_reader :constants_to_files
    end
    
    attr_accessor :path, :constants
    delegate :constants_to_files, :to => 'self.class'
  
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
      new_constants.each do |new_constant|
        (constants_to_files[new_constant] ||= []) << self
      end
      @constants |= new_constants
      retrieve_associated_files.each {|file| file.add_constants(@constants)} if @associated_files
    end
    
    def delete_constant(const_name)
      delete_from_constants_to_files(const_name)
      @constants.delete(const_name)
    end
    
    def associate_with(other_loaded_file)
      (@associated_files ||= []) << other_loaded_file
    end
    
    def retrieve_associated_files
      associated_files, @associated_files = @associated_files, nil
      associated_files
    end
    
    def require_path
      @path.sub(/\.rb\Z/, '')
    end
    
    def self.each_file_with_const(const_name, &block)
      if files = constants_to_files[const_name]
        files.dup.each(&block)
      end
    end
    
  private
    
    def delete_from_constants_to_files(const_name)
      if files = constants_to_files[const_name]
        files.delete(self)
        constants_to_files.delete(const_name) if files.empty?
      end
    end
    
    def current_mtime
      File.file?(@path) ? File.mtime(@path) : nil
    end
  end
end

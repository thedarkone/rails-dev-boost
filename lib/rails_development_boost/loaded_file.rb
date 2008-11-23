module RailsDevelopmentBoost
  class LoadedFile
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
    
  private
  
    def current_mtime
      File.file?(@path) ? File.mtime(@path) : nil
    end
  end
end

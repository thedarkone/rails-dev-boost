module SelectiveConstantUnload
  class LoadedFile
    attr_accessor :constants
  
    def initialize(path, constants=[])
      @path, @constants, @mtime = path, constants, File.mtime(path)
    end
  
    def changed?
      !File.exist?(@path) || File.mtime(@path) != @mtime
    end
  end
end

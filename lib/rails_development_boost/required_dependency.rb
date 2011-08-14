module RailsDevelopmentBoost
  class RequiredDependency < Array
    def initialize(currently_loading)
      super(caller)
      @currently_loading = currently_loading
    end
    
    def related_files
      files = []
      each_autoloaded_file do |file_path|
        if @currently_loading == file_path
          files << @currently_loading
          break
        elsif LoadedFile.loaded?(file_path)
          files << file_path
        end
      end
      files.uniq
    end
    
    private
    def each_autoloaded_file
      each do |stack_line|
        if file_path = extract_file_path(stack_line)
          yield file_path
        end
      end
    end
    
    def extract_file_path(stack_line)
      if m = stack_line.match(/\A(.*):[0-9]+(?::in `[^']+')?\Z/)
        m[1]
      end
    end
  end
end
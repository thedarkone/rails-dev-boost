module RailsDevelopmentBoost
  module LoadablePatch
    def self.apply!
      Object.send :include, LoadablePatch
    end
    
    def load(file, wrap = false)
      expanded_path = File.expand_path(file)
      # force the manual #load calls for autoloadable files to go through the AS::Dep stack
      if ActiveSupport::Dependencies.in_autoload_path?(expanded_path)
        expanded_path << '.rb' unless expanded_path.ends_with?('.rb')
        ActiveSupport::Dependencies.load_file(expanded_path) unless LoadedFile.loaded?(expanded_path)
      else
        super
      end
    end
  end
end
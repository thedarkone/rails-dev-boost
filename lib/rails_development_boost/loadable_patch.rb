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
        unless LoadedFile.loaded?(expanded_path)
          ActiveSupport::Dependencies.load_file(expanded_path)
          if LoadedFile.loaded?(expanded_path) && (file = LoadedFile.for(expanded_path)).decorator_like?
            file.associate_to_greppable_constants
          end
        end
      else
        super
      end
    end
  end
end
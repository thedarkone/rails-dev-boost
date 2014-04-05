module RailsDevelopmentBoost
  module LoadablePatch
    def self.apply!
      Object.send :include, LoadablePatch
    end
    
    def load(file, wrap = false)
      real_path = DependenciesPatch::Util.load_path_to_real_path(file)
      # force the manual #load calls for autoloadable files to go through the AS::Dep stack
      if ActiveSupport::Dependencies.in_autoload_path?(real_path)
        ActiveSupport::Dependencies.load_file_from_explicit_load(real_path)
      else
        super
      end
    end
  end
end

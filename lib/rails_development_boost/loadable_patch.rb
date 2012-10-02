module RailsDevelopmentBoost
  module LoadablePatch
    def self.apply!
      Object.send :include, LoadablePatch
    end
    
    def load(file, wrap = false)
      expanded_path = File.expand_path(file)
      # force the manual #load calls for autoloadable files to go through the AS::Dep stack
      if ActiveSupport::Dependencies.in_autoload_path?(expanded_path)
        expanded_path << '.rb' unless expanded_path =~ /\.(rb|rake)\Z/
        ActiveSupport::Dependencies.load_file_from_explicit_load(expanded_path)
      else
        super
      end
    end
  end
end

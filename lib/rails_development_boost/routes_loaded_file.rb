module RailsDevelopmentBoost
  class RoutesLoadedFile < LoadedFile
    def decorator_like?
      false
    end
    
    def changed?
      false
    end
    
    def schedule_consts_for_unloading!
      Reloader.routes_reloader.force_execute!
    end
    
    def add_constants(new_constants)
    end
    
    def clean_up_if_necessary
    end
    
    def self.for(file_path)
      LOADED.loaded?(file_path) ? LOADED[file_path] : LOADED[file_path] = new(file_path)
    end
  end
end
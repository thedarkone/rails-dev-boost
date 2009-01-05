module RailsDevelopmentBoost
  module CachedTemplatesPatch
    module TemplatePatch
  
      def self.included(template_class)
        template_class.send :remove_method, :_unmemoized_source
      end
  
      attr_reader :previously_last_modified
  
      def _unmemoized_source
        record_last_modified
        File.read(filename)
      end
  
      def record_last_modified
        @previously_last_modified = current_mtime
      end
  
      def current_mtime
        File.stat(filename).mtime
      end
  
      def stale?
        previously_last_modified.nil? || previously_last_modified < current_mtime
      rescue Errno::ENOENT => e
        raise TemplateDeleted
      end
  
      def reset_cache_if_stale!
        if stale?
          ['source', 'compiled_source'].each do |attr|          
            ivar = ActiveSupport::Memoizable::MEMOIZED_IVAR.call(attr)
            instance_variable_get(ivar).clear if instance_variable_defined?(ivar)
          end
          undef_my_compiled_methods!
        end
        self
      end
  
    end
  end
end
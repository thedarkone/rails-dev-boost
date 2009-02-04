module RailsDevelopmentBoost
  module CachedTemplatesPatch
    class AutoReloadingTemplate < ActionView::Template
      
      module Unfreezable
        def freeze; self; end
      end
  
      def initialize(*args)
        super
        @my_compiled_methods = []
        
        # we don't ever want to get frozen
        extend Unfreezable
      end
      
      attr_reader :previously_last_modified
      
      def _unmemoized_source
        @previously_last_modified = current_mtime
        super
      end
  
      def current_mtime
        File.mtime(filename)
      end
  
      def stale?
        previously_last_modified.nil? || previously_last_modified < current_mtime
      rescue Errno::ENOENT => e
        raise TemplateDeleted
      end
  
      def reset_cache_if_stale!
        if stale?
          flush_cache 'source', 'compiled_source'
          undef_my_compiled_methods!
        end
        self
      end
      
      def undef_my_compiled_methods!
        @my_compiled_methods.each {|comp_method| ActionView::Base::CompiledTemplates.send :remove_method, comp_method}
        @my_compiled_methods.clear
      end

      def compile!(render_symbol, local_assigns)
        super
        @my_compiled_methods << render_symbol
      end
      
      def recompile?
        false
      end
      
    end
  end
end
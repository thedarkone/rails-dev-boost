module RailsDevelopmentBoost
  module CachedTemplatesPatch
    module RenderablePatch
      
      def self.included(template_klass)
        template_klass.alias_method_chain :compile!, :method_name_tracking
      end
    
      def undef_my_compiled_methods!
        if @_my_compiled_methods
          @_my_compiled_methods.each {|comp_method| ActionView::Base::CompiledTemplates.send :remove_method, comp_method}
          @_my_compiled_methods.clear
        end
      end

      def compile_with_method_name_tracking!(render_symbol, local_assigns)
        compile_without_method_name_tracking!(render_symbol, local_assigns)
        (@_my_compiled_methods ||= []) << render_symbol
      end
    
      def recompile?(symbol)
        !ActionView::Base::CompiledTemplates.method_defined?(symbol)
      end
    
    end
  end
end
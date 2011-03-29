module RailsDevelopmentBoost
  module DependenciesPatch
    module InstrumentationPatch
      module LoadedFile
        def boost_inspect
          "\#<LoadedFile #{relative_path} #{inspect_constants(@constants)}>"
        end
        
        def add_constants_with_instrumentation(new_constants)
          ActiveSupport::Dependencies.boost_log('ADD_CONSTANTS', "#{boost_inspect} <- #{inspect_constants(new_constants)}")
          add_constants_without_instrumentation(new_constants)
        end

      private
        RAILS_ROOT = /\A#{Rails.root.to_s}/
        
        def inspect_constants(constants_arr)
          "[#{constants_arr.join(', ')}]"
        end

        def relative_path
          @path.sub(RAILS_ROOT, '')
        end
        
        def self.included(base)
          base.alias_method_chain :add_constants, :instrumentation
        end
      end
      
      def self.apply!
        ActiveSupport::Dependencies.extend self
        RailsDevelopmentBoost::LoadedFile.send :include, LoadedFile
      end
      
      def unload_modified_files
        boost_log('--- START ---')
        super
        boost_log('--- END ---')
      end
      
      def load_file_without_constant_tracking(path, *args)
        other_args = ", #{args.map(&:inspect).join(', ')}" if args.any?
        boost_log('LOAD', "load_file(#{path.inspect}#{other_args})")
        super
      end
      
      def remove_constant_without_handling_of_connections(const_name)
        boost_log('REMOVE_CONST', const_name)
        super
      end
      
      def boost_log(action, msg = nil)
        action, msg = msg, action unless msg
        raw_boost_log("#{ "[#{action}] " if action}#{msg}")
      end
      
      private
      def unprotected_remove_constant(const_name)
        boost_log('REMOVING', const_name)
        @removal_nesting = (@removal_nesting || 0) + 1
        super
      ensure
        @removal_nesting -= 1
      end
      
      def error_loading_file(file_path, e)
        boost_log('ERROR_WHILE_LOADING', "#{loaded_file_for(file_path).boost_inspect}: #{e.inspect}")
        super
      end
      
      def unload_modified_file(file)
        boost_log('CHANGED', "#{file.boost_inspect}")
        super
      end
      
      def unload_containing_file(const_name, file)
        boost_log('UNLOAD_CONTAINING_FILE', "#{const_name} -> #{file.boost_inspect}")
        super
      end
      
      def remove_explicit_dependency(const_name, depending_const)
        boost_log('EXPLICIT_DEPENDENCY', "#{const_name} -> #{depending_const}")
        super
      end
      
      def remove_dependent_constant(original_module, dependent_module)
        boost_log('DEPENDENT_MODULE', "#{original_module._mod_name} -> #{dependent_module._mod_name}")
        super
      end
      
      def remove_autoloaded_parent_module(initial_object, parent_object)
        boost_log('REMOVE_PARENT', "#{initial_object._mod_name} -> #{parent_object._mod_name}")
        super
      end
      
      def remove_child_module_constant(parent_object, child_constant)
        boost_log('REMOVE_CHILD', "#{parent_object._mod_name} -> #{child_constant._mod_name}")
        super
      end
      
      def remove_nested_constant(parent_const, child_const)
        boost_log('REMOVE_NESTED', "#{parent_const} :: #{child_const.sub(/\A#{parent_const}::/, '')}")
        super
      end
      
      def raw_boost_log(msg)
        Rails.logger.info("[DEV-BOOST] #{"\t" * (@removal_nesting || 0)}#{msg}")
      end
    end
  end
end
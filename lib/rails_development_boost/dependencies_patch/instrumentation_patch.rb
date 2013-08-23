module RailsDevelopmentBoost
  module DependenciesPatch
    module InstrumentationPatch
      module Instrumenter
        delegate :boost_log, :boost_log_nested, :boost_log_schedule_const_removal, :to => 'ActiveSupport::Dependencies'
        
        def self.included(mod)
          mod.extend(ClassMethods)
        end
        
        module ClassMethods
          def included(klass)
            (public_instance_methods(false) + private_instance_methods(false) + protected_instance_methods(false)).each do |method|
              if m = method.to_s.match(/\A(.+)_with_(.+)\Z/)
                meth_name, extension = m[1], m[2]
                extension.sub!(/[?!=]\Z/) do |modifier|
                  meth_name << modifier
                  ''
                end
                klass.alias_method_chain meth_name, extension
              end
            end

            super
          end
        end
      end
      
      module LoadedFile
        include Instrumenter
        
        def boost_inspect
          "\#<LoadedFile #{relative_path} #{inspect_constants(@constants)}>"
        end
        
        def add_constants_with_instrumentation(new_constants)
          boost_log('ADD_CONSTANTS', "#{boost_inspect} <- #{inspect_constants(new_constants)}")
          add_constants_without_instrumentation(new_constants)
        end
        
        def dependent_file_schedule_for_unloading_with_instrumentation!(dependent_file)
          boost_log('SCHEDULE_DEPENDENT', "#{boost_inspect}: #{dependent_file.boost_inspect}")
          dependent_file_schedule_for_unloading_without_instrumentation!(dependent_file)
        end
        
        def schedule_const_for_unloading_with_instrumentation(const_name)
          boost_log_schedule_const_removal('SCHEDULE_REMOVAL', const_name, const_name)
          schedule_const_for_unloading_without_instrumentation(const_name)
        end

      private
        RAILS_ROOT = /\A#{Rails.root.to_s}/
        
        def inspect_constants(constants_arr)
          "[#{constants_arr.join(', ')}]"
        end

        def relative_path
          @path.sub(RAILS_ROOT, '')
        end
        
        def self.included(klass)
          klass.singleton_class.send :include, ClassMethods
          super
        end
        
        module ClassMethods
          include Instrumenter
          
          def unload_modified_with_instrumentation!
            boost_log('--- START ---')
            unload_modified_without_instrumentation!.tap do
              boost_log('--- END ---')
            end
          end
          
          def schedule_containing_file_with_instrumentation(const_name, file)
            boost_log('SCHEDULE_CONTAINING_FILE', "#{const_name} -> #{file.boost_inspect}")
            schedule_containing_file_without_instrumentation(const_name, file)
          end
        end
      end
      
      module Files
        include Instrumenter
        
        def schedule_modified_file_with_instrumentation(file)
          boost_log('CHANGED', "#{file.boost_inspect}")
          boost_log_nested { schedule_modified_file_without_instrumentation(file) }
        end
        
        def schedule_decorator_file_with_instrumentation(file)
          boost_log('SCHEDULE_DECORATOR_FILE', "#{file.boost_inspect}")
          schedule_decorator_file_without_instrumentation(file)
        end
      end
      
      def self.apply!
        unless applied?
          ActiveSupport::Dependencies.extend self
          RailsDevelopmentBoost::LoadedFile.send :include, LoadedFile
          RailsDevelopmentBoost::LoadedFile::Files.send :include, Files
        end
      end
      
      def self.applied?
        ActiveSupport::Dependencies.singleton_class.include?(self)
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
      
      def load_file_from_explicit_load(expanded_path)
        boost_log('EXPLICIT_LOAD_REQUEST', expanded_path)
        super
      end
      
      def boost_log(action, msg = nil)
        action, msg = msg, action unless msg
        raw_boost_log("#{ "[#{action}] " if action}#{msg}")
      end
      
      def boost_log_schedule_const_removal(action, msg, const_name)
        action = "#{action} | #{ActiveSupport::Dependencies.constants_to_remove.seen?(const_name) ? 'SKIP' : 'SCHEDULED'}"
        boost_log(action, msg)
      end
      
      def boost_log_nested
        @removal_nesting = (@removal_nesting || 0) + 1
        yield
      ensure
        @removal_nesting -= 1
      end
      
      private
      def schedule_dependent_constants_for_removal(const_name, object)
        boost_log_nested { super }
      end
      
      def error_loading_file(file_path, e)
        description = RailsDevelopmentBoost::LoadedFile.loaded?(file_path) ? RailsDevelopmentBoost::LoadedFile.for(file_path).boost_inspect : file_path
        boost_log('ERROR_WHILE_LOADING', "#{description}: #{e.inspect}")
        super
      end
      
      def remove_explicit_dependency(const_name, depending_const)
        boost_log_schedule_const_removal('EXPLICIT_DEPENDENCY', "#{const_name} -> #{depending_const}", depending_const)
        super
      end
      
      def remove_dependent_constant(original_module, dependent_module)
        const_name = dependent_module._mod_name
        boost_log_schedule_const_removal('DEPENDENT_MODULE', "#{original_module._mod_name} -> #{const_name}", const_name)
        super
      end
      
      def remove_autoloaded_parent_module(initial_object, parent_object)
        const_name = parent_object._mod_name
        boost_log_schedule_const_removal('REMOVE_PARENT', "#{initial_object._mod_name} -> #{const_name}", const_name)
        super
      end
      
      def remove_child_module_constant(parent_object, full_child_const_name)
        boost_log_schedule_const_removal('REMOVE_CHILD', "#{parent_object._mod_name} -> #{full_child_const_name}", full_child_const_name)
        super
      end
      
      def remove_nested_constant(parent_const, child_const)
        boost_log_schedule_const_removal('REMOVE_NESTED', "#{parent_const} :: #{child_const.sub(/\A#{parent_const}::/, '')}", child_const)
        super
      end
      
      def raw_boost_log(msg)
        Rails.logger.info("[DEV-BOOST] #{"  " * (@removal_nesting || 0)}#{msg}")
      end
    end
  end
end
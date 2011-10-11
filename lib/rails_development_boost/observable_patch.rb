module RailsDevelopmentBoost
  module ObservablePatch
    extend self
    
    def self.apply!
      patch = self
      
      if non_ruby_lib_implementation?
        ActiveModel::Observing::ClassMethods # post c2ca73c9 compatibility
      else
        require 'observer'
        Observable
      end.class_eval do
        include patch
        alias_method_chain :add_observer, :unloading
      end
    end
    
    def self.non_ruby_lib_implementation?
      defined?(ActiveModel::Observing::ClassMethods) && ActiveModel::Observing::ClassMethods.public_instance_methods(false).map(&:to_s).include?('add_observer')
    end
    
    def add_observer_with_unloading(*args)
      if kind_of?(Module)
        my_module, observer_module = ObservablePatch._get_module(self), ObservablePatch._get_module(args.first)
      
        ActiveSupport::Dependencies.add_explicit_dependency(my_module, observer_module)
        ActiveSupport::Dependencies.add_explicit_dependency(observer_module, my_module)
      end
      
      add_observer_without_unloading(*args)
    end
    
    def _get_module(object)
      object.kind_of?(Module) ? object : object.class
    end
  end
end
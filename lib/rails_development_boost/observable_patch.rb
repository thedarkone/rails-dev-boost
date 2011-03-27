module RailsDevelopmentBoost
  module ObservablePatch
    extend self
    
    def self.apply!
      Observable.send :include, self
      Observable.alias_method_chain :add_observer, :unloading
    end
    
    def add_observer_with_unloading(observer)
      if kind_of?(Module)
        my_module, observer_module = ObservablePatch._get_module(self), ObservablePatch._get_module(observer)
      
        ActiveSupport::Dependencies.add_explicit_dependency(my_module, observer_module)
        ActiveSupport::Dependencies.add_explicit_dependency(observer_module, my_module)
      end
      
      add_observer_without_unloading(observer)
    end
    
    def _get_module(object)
      object.kind_of?(Module) ? object : object.class
    end
  end
end
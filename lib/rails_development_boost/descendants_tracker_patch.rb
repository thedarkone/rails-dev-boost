require 'active_support/descendants_tracker'

module RailsDevelopmentBoost
  module DescendantsTrackerPatch
    def self.apply!
      # removing the .clear method across all Rails/Ruby versions
      begin
        ActiveSupport::DescendantsTracker.send(:remove_method, :clear)
      rescue NameError
      end
      begin
        ActiveSupport::DescendantsTracker.singleton_class.send(:remove_method, :clear)
      rescue NameError
      end
      ActiveSupport::DescendantsTracker.extend self
    end
    
    def delete(klass)
      class_variable_get(:@@direct_descendants).tap do |direct_descendants|
        direct_descendants.delete(klass)
        direct_descendants.each_value {|descendants| descendants.delete(klass)}
      end
    end
    
    def clear
    end
  end
end
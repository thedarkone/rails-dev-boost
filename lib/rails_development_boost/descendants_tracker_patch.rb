require 'active_support/descendants_tracker'

module RailsDevelopmentBoost
  module DescendantsTrackerPatch
    def self.apply!
      ActiveSupport::DescendantsTracker.extend self
      ActiveSupport::DescendantsTracker.singleton_class.remove_possible_method :clear
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
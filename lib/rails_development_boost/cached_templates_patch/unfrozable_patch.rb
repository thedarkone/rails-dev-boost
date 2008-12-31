module RailsDevelopmentBoost
  module CachedTemplatesPatch
    module UnfrozablePatch
    
      def self.included(frozable)
        frozable.class_eval do
          def freeze
            self
          end
        end
      end
    
    end
  end
end
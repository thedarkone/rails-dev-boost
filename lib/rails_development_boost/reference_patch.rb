require 'active_support/dependencies'

module RailsDevelopmentBoost
  module ReferencePatch
    if defined?(ActiveSupport::Dependencies::ClassCache) # post Rails' f345e2380cac2560f3bb
      def self.apply!
        ActiveSupport::Dependencies::ClassCache.send :include, self
      end
      
      def loose!(const_name)
        @store.delete(const_name)
        @store.delete("::#{const_name}") # constantize is sometimes weird like that
      end
    else
      def self.apply!
        ActiveSupport::Dependencies::Reference.cattr_reader :constants
        ActiveSupport::Dependencies::Reference.extend ClassMethods
      end

      module ClassMethods
        def loose!(const_name)
          constants.delete(const_name)
          constants.delete("::#{const_name}") # constantize is sometimes weird like that
        end
      end
    end
  end
end
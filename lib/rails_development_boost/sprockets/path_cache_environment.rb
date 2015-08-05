module RailsDevelopmentBoost
  module Sprockets
    module PathCacheEnvironment
      def cached
        result = super
        result.singleton_class.prepend(RailsDevelopmentBoost::Sprockets::PathCache)
        result
      end
    end
  end
end

 module RailsDevelopmentBoost
   module Sprockets
     module PathCache
       # @!attribute[r] resolve_path_cache
       #   The path resolution cache. This is keyed by path, and the value is either a string
       #   containing the resolved path, or false to indicate that it should not be cached.
       mattr_reader :resolve_path_cache
       @@resolve_path_cache = {}

       def resolve(path, options = {})
         cached_path = PathCache.resolve_path_cache[path]
         return cached_path if cached_path

         result = super
         return result if cached_path == false || result.first.nil?

         raw_path = parse_asset_uri(result.first).first
         if Bundler.rubygems.all_specs.any? { |s| raw_path.start_with?(s.full_gem_path) }
           PathCache.resolve_path_cache[path] = result
         else
           PathCache.resolve_path_cache[path] = false
         end
         result
       end
     end
   end
 end

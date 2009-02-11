module RailsDevelopmentBoost
  module CachedTemplatesPatch
    module BasePatch
      
      def initialize_with_view_path_cache_reset(view_paths = [], assigns_for_first_render = {}, controller = nil)
        initialize_without_view_path_cache_reset(view_paths, assigns_for_first_render, controller)
        @view_paths.map(&:new_request!)
      end
      
      module ClassMethods
        def process_view_paths(value)
          ActionView::PathSet.new(Array(value).map{|path| to_reloading_path(path)})
        end
        
        def to_reloading_path(path)
          path.kind_of?(AutoReloadingPath) ? path : AutoReloadingPath.new(path.to_s)
        end
      end
      
      def self.included(action_view_base)
        action_view_base.alias_method_chain :initialize, :view_path_cache_reset
        
        action_view_base.metaclass.send :remove_method, :process_view_paths
        action_view_base.extend ClassMethods
        # convert already loaded view paths
        ActionController::Base.view_paths.map! {|path| action_view_base.to_reloading_path(path)}
      end
      
    end
  end
end
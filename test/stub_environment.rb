require 'active_support'
require 'action_controller/dispatcher'

module ActionController
  def self.define_nested_module(name)
    name.to_s.split('::').inject(self) { |namespace, name| namespace.const_set(name, Module.new) }
  end
  
  # Routing::Routes.reload
  routes = define_nested_module("Routing::Routes")
  def routes.reload; end
  
  # ActionController::Base.view_paths.reload!
  base = define_nested_module("Base")
  def base.view_paths; self; end
  def base.reload!; end
  
  # ActionView::Helpers::AssetTagHelper::AssetTag::Cache.clear
  asset_cache = define_nested_module("ActionView::Helpers::AssetTagHelper::AssetTag::Cache")
  def asset_cache.clear; end
end

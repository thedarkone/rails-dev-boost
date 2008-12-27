require 'active_support'

require 'action_controller'
require 'action_controller/dispatcher'

module ActionController
  def self.define_nested_module(name)
    name.to_s.split('::').inject(self) do |namespace, name|
      begin
        namespace.const_get(name)
      rescue LoadError
        namespace.const_set(name, Module.new)
      end
    end
  end
  
  Dispatcher.class_eval(<<-RUBY)
    if defined? @@middleware
      m = @@middleware
      def m.build(*a) end
    end
  RUBY
  
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

require 'active_record'
ActiveRecord::Base.class_eval { def self.columns; []; end }
ActiveRecord::Base.class_eval { def self.inspect; super; end }
ActiveRecord::Associations::HasManyAssociation.class_eval { def construct_sql; end }

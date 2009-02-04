module RailsDevelopmentBoost
  module CachedTemplatesPatch
    class TemplateDeleted < ActionView::ActionViewError
    end
  
    def self.apply!
      ActionView::Base.send :include, BasePatch
    end
    
    autoload :AutoReloadingTemplate,'rails_development_boost/cached_templates_patch/auto_reloading_template'
    autoload :AutoReloadingPath,    'rails_development_boost/cached_templates_patch/auto_reloading_path'
    autoload :BasePatch,            'rails_development_boost/cached_templates_patch/base_patch'
  end
end
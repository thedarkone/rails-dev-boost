module RailsDevelopmentBoost
  module CachedTemplatesPatch
    class TemplateDeleted < ActionView::ActionViewError
    end
  
    def self.apply!
      ActionView::PathSet::Path.send      :include, PathPatch
      ActionView::Template.send           :include, TemplatePatch
      ActionView::Template.send           :include, UnfrozablePatch
      ActionView::RenderablePartial.send  :include, UnfrozablePatch
    end
    
    autoload :PathPatch,        'rails_development_boost/cached_templates_patch/path_patch'
    autoload :TemplatePatch,    'rails_development_boost/cached_templates_patch/template_patch'
    autoload :UnfrozablePatch,  'rails_development_boost/cached_templates_patch/unfrozable_patch'
  end
end
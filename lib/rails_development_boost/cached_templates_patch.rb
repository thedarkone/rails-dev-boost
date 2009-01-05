module RailsDevelopmentBoost
  module CachedTemplatesPatch
    class TemplateDeleted < ActionView::ActionViewError
    end
  
    def self.apply!
      ActionView::PathSet::Path.send      :include, PathPatch
      ActionView::Template.send           :include, TemplatePatch
      ActionView::Template.send           :include, UnfrozablePatch
      ActionView::RenderablePartial.send  :include, UnfrozablePatch
      # we need to patch the Renderable module's methods *only* in context of the Template class
      ActionView::Template.send           :include, RenderablePatch
    end
    
    autoload :PathPatch,        'rails_development_boost/cached_templates_patch/path_patch'
    autoload :TemplatePatch,    'rails_development_boost/cached_templates_patch/template_patch'
    autoload :UnfrozablePatch,  'rails_development_boost/cached_templates_patch/unfrozable_patch'
    autoload :RenderablePatch,  'rails_development_boost/cached_templates_patch/renderable_patch'
  end
end
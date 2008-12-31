module RailsDevelopmentBoost
  module CachedTemplatesPatch
    module PathPatch
      extend ActiveSupport::Memoizable
      
      def self.included(path_class)
        path_class.class_eval do
          alias_method :old_get, :[]
          alias_method :[], :new_get
          remove_method :reload!
        end
      end
    
      def new_get(path)
        if template = old_get(path)
          begin
            template.reset_cache_if_stale!
          rescue TemplateDeleted
            unregister_template(template)
            new_get(path)
          end
        else
          load_matching_templates(path)
          old_get(path)
        end
      end
    
      # we lazy load all the templates on the fly
      def reload!
        @paths ||= {}
        @disk_cache = {}
        @loaded = true
      end
    
      # remove (probably deleted) template from cache
      def unregister_template(template)
        @paths.delete(template.path)
        if @paths[template.path_without_extension] == template
          @paths.delete(template.path_without_extension)
          if stand_in = @paths.values.find {|stand_in_candidate| stand_in_candidate.path_without_extension == template.path_without_extension}
            @paths[stand_in.path_without_extension] = stand_in
          end
        end
      end
    
      def register_template_from_file(template_file)
        template_relative_path = template_file.split("#{@path}/").last
        register_template(ActionView::Template.new(template_relative_path, self)) unless @paths[template_relative_path]
      end
  
      def register_template(template)
        @paths[template.path] = template
        @paths[template.path_without_extension] ||= template
      end
    
      # find and register all potential templates
      def load_matching_templates(path)
        template_file_candidates_for(path).each {|template_file| register_template_from_file(template_file)}
      end
    
      # we need to be looking for all the potential template extensions, e.g. products/index should match products/index.html.erb etc.
      def template_file_candidates_for(path)
        hit_disk_for_matching_templates(glob_template_matcher_for(path))
      end
      
      # @disk_cache is useful for apps using inherit_views plugin
      def hit_disk_for_matching_templates(template_match_str)
        @disk_cache[template_match_str] ||= Dir.glob(template_match_str).reject {|file_or_dir| File.directory?(file_or_dir)}
      end
    
      def glob_template_matcher_for(path)
        basename_without_template_extensions, dir = File.basename(path).match(/\A[^.]*/)[0], File.dirname(path)
        "#{File.join(@path, dir, basename_without_template_extensions)}*"
      end
      memoize :glob_template_matcher_for
  
    end
  end
end
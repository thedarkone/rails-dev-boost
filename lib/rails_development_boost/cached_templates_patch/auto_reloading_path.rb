module RailsDevelopmentBoost
  module CachedTemplatesPatch
    class AutoReloadingPath < ActionView::Template::Path
      extend ActiveSupport::Memoizable
      
      def initialize(path)
        super
        @paths = {}
        new_request!
      end
      
      def new_request!
        @disk_cache = {}
      end
      
      def [](path)
        if found_template = @paths[path]
          begin
            found_template.reset_cache_if_stale!
          rescue TemplateDeleted
            unregister_template(found_template)
            self[path]
          end
        else
          load_matching_templates(path)
          @paths[path]
        end
      end
      
      def register_template_from_file(template_file)
        template_relative_path = template_file.split("#{@path}/").last
        register_template(AutoReloadingTemplate.new(template_relative_path, self)) unless @paths[template_relative_path]
      end
      
      def register_template(template)
        template.accessible_paths.each do |path|
          @paths[path] = template
        end
      end
      
      # remove (probably deleted) template from cache
      def unregister_template(template)
        template.accessible_paths.each do |template_path|
          @paths.delete(template_path) if @paths[template_path] == template
        end
        # fill in any newly created gaps
        @paths.values.uniq.each do |template|
          template.accessible_paths.each {|path| @paths[path] ||= template}
        end
      end
      
      # find and register all potential templates
      def load_matching_templates(path)
        template_file_candidates_for(path).each {|template_file| register_template_from_file(template_file)}
      end
      
      # we need to be looking for all the potential template extensions, e.g. products/index should match products/index.html.erb etc.
      def template_file_candidates_for(path)
        hit_disk_for_matching_templates(glob_template_matcher_for(path))
      end
      
      # @disk_cache is very useful for apps using inherit_views plugin
      def hit_disk_for_matching_templates(template_match_str)
        @disk_cache[template_match_str] ||= Dir.glob(template_match_str).reject {|file_or_dir| File.directory?(file_or_dir)}
      end
      
      # search str for Dir.glob matching every possible combination of extension/locale/format
      def glob_template_matcher_for(path)
        basename_without_template_extensions, dir = File.basename(path)[/\A[^.]*/], File.dirname(path)
        "#{File.join(@path, dir, basename_without_template_extensions)}*"
      end
      memoize :glob_template_matcher_for
      
    end    
  end
end
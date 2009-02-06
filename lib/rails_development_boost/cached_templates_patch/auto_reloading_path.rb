module RailsDevelopmentBoost
  module CachedTemplatesPatch
    class AutoReloadingPath < ActionView::Template::Path
      
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
          load_all_templates_from_dir(templates_dir_from_path(path))
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
      
      # load all templates from the directory of the requested template
      def load_all_templates_from_dir(dir)
        # hit disk only once per template-dir/request
        @disk_cache[dir] ||= template_files_from_dir(dir).each {|template_file| register_template_from_file(template_file)}
      end
      
      def templates_dir_from_path(path)
        File.join(@path, File.dirname(path))
      end
      
      # get all the template filenames from the dir
      def template_files_from_dir(dir)
        Dir.glob("#{dir}/*")
      end
      
    end    
  end
end
require 'rb-fsevent'
require 'monitor'

module RailsDevelopmentBoost
  module Async
    extend self
    
    MONITOR = Monitor.new
    
    def heartbeat_check!
      running? ? re_raise_unload_error_if_any : start!
    end
    
    def synchronize
      MONITOR.synchronize { yield }
    end
    
    private
    
    def start!
      @reactor = Reactor.new
      @reactor.watch(ActiveSupport::Dependencies.autoload_paths) {|changed_dirs| unload_affected(changed_dirs)}
      @reactor.start!
    end
    
    def running?
      @reactor.try(:alive?)
    end
    
    def re_raise_unload_error_if_any
      if e = @unload_error
        @unload_error = nil
        raise e, e.message, e.backtrace
      end
    end
    
    def unload_affected(changed_dirs)
      changed_dirs = changed_dirs.map {|changed_dir| File.expand_path(changed_dir).chomp(File::SEPARATOR)}
      
      synchronize do
        LoadedFile::LOADED.values.each do |file|
          if changed_dirs.any? {|changed_dir| file.path.starts_with?(changed_dir)} && file.changed?
            LoadedFile::LOADED.unload_modified_file(file)
          end
        end
      end
    rescue Exception => e
      @unload_error ||= e
    end
    
    class Reactor
      delegate :alive?, :to => '@thread'
      delegate :watch, :to => '@watcher'
      
      def initialize
        @watcher = FSEvent.new
      end
      
      def start!
        @thread = Thread.new { @watcher.run }
      end
    end
  end
end
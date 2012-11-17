require 'rb-fsevent'
require 'monitor'

module RailsDevelopmentBoost
  module Async
    class Middleware
      def initialize(app)
        @app = app
      end
      
      def call(env)
        if DependenciesPatch.applied? && DependenciesPatch.async?
          Async.synchronize { @app.call(env) }
        else
          @app.call(env)
        end
      end
    end
    
    extend self
    
    MONITOR = Monitor.new
    
    def heartbeat_check!
      if @reactor
        unless @reactor.alive?
          @reactor.stop
          @reactor = nil
          start!
        end
        re_raise_unload_error_if_any
      else
        start!
      end
      @unloaded_something.tap { @unloaded_something = false }
    end
    
    def synchronize
      MONITOR.synchronize { yield }
    end
    
    private
    
    def start!
      @reactor = Reactor.new
      @reactor.watch(ActiveSupport::Dependencies.autoload_paths) {|changed_dirs| unload_affected(changed_dirs)}
      @reactor.start!
      self.unloaded_something = LoadedFile.unload_modified! # don't miss-out on any of the file changes as the async thread hasn't been started as of yet
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
        self.unloaded_something = LoadedFile::LOADED.each_file_unload_if_changed do |file|
          changed_dirs.any? {|changed_dir| file.path.starts_with?(changed_dir)} && file.changed?
        end
      end
    rescue Exception => e
      @unload_error ||= e
    end
    
    def unloaded_something=(value)
      @unloaded_something ||= value
    end
    
    class Reactor
      delegate :alive?, :to => '@thread'
      delegate :watch, :stop, :to => '@watcher'
      
      def initialize
        @watcher = FSEvent.new
      end
      
      def start!
        @thread = Thread.new { @watcher.run }
      end
    end
  end
end
require 'listen'
require 'thread'
require 'set'

module RailsDevelopmentBoost
  module Async
    # Not using Listen gem directly, because I don't want to be storing/checking .rb files' SHA contents and would like to rely on mtime values exclusively.
    module Reactor
      extend self
      attr_reader :listen_load_error
      
      def get
        if impl = implementation
          impl.new
        end
      end
      
      def implementation
        defined?(@implementation) ? @implementation : (@implementation = find_usable_implementation)
      end
      
      def find_usable_implementation
        [Darwin, Linux, Windows].find(&:usable?)
      rescue Listen::DependencyManager::Error => e
        @listen_load_error ||= "Error message from the `listen` gem:\n\t" << e.message.gsub("\n", "\n\t")
        nil
      end
      
      class Base
        def initialize
          @watcher     = create_watcher
          @directories = Set.new
        end
        
        def watch(directories, &block)
          @directories.merge(directories)
          watch_internal(directories, &block)
        end

        def start!
          @thread = Thread.new { start_watcher! }
        end
        
        def stop
          @watcher.stop
          stop_thread
        end
        
        def alive_and_watching?(directories)
          @thread.alive? && directories.all? {|directory| @directories.include?(directory)}
        end
        
        private
        def watch_internal(directories, &block)
          @watcher.watch(directories, &block)
        end
        
        def stop_thread
          @thread.join if @thread
        end
        
        def start_watcher!
          @watcher.run
        end
        
        def self.usable?
          if adapter = corresponding_listen_adapter
            adapter.usable?
          end
        end
        
        def self.corresponding_listen_adapter
          Listen::Adapters.const_get(name[/[^:]+\Z/])
        rescue NameError
        end
      end

      class Darwin < Base
        private
        def create_watcher
          FSEvent.new
        end
      end

      # Errors, comments and other gotchas taken from Listen gem (https://github.com/guard/listen)
      class Linux < Base
        EVENTS = [:recursive, :attrib, :create, :delete, :move, :close_write]
        
        # The message to show when the limit of inotify watchers is not enough
        #
        INOTIFY_LIMIT_MESSAGE = <<-EOS.gsub(/^\s*/, '')
          Listen error: unable to monitor directories for changes.

          Please head to https://github.com/guard/listen/wiki/Increasing-the-amount-of-inotify-watchers
          for information on how to solve this issue.
        EOS
        
        private
        def watch_internal(directories)
          directories.each do |directory|
            @watcher.watch(directory, *EVENTS) do |event|
              yield [File.dirname(event.absolute_name)] unless root?(event) || file_event_on_a_dir?(event)
            end
          end
        rescue Errno::ENOSPC
          abort(INOTIFY_LIMIT_MESSAGE)
        end
        
        def root?(event) # Event on root directory
          event.name.empty? # same as event.name == ""
        end
        
        # INotify reports changes to files inside directories as events
        # on the directories themselves too.
        #
        # @see http://linux.die.net/man/7/inotify
        def file_event_on_a_dir?(event)
          # event.flags.include?(:isdir) and event.flags & [:close, :modify] != []
          flags = event.flags
          flags.include?(:isdir) && (flags.include?(:close) || flags.include?(:modify))
        end
        
        def create_watcher
          INotify::Notifier.new
        end
        
        def stop_thread
          Thread.kill(@thread) if @thread
        end
      end
      
      class Windows < Base
        private
        def watch_internal(directories)
          directories.each do |directory|
            @watcher.watch_recursively(directory) do |change|
              yield [File.dirname(change.path)]
            end
          end
        end
        
        def create_watcher
          WDM::Monitor.new
        end
        
        def start_watcher!
          @watcher.run!
        end
      end
    end
  end
end
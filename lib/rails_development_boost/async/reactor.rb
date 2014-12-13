require 'thread'
require 'set'

module RailsDevelopmentBoost
  module Async
    # Not using Listen gem directly, because I don't want to be storing/checking .rb files' SHA contents and would like to rely on mtime values exclusively.
    module Reactor
      class MissingNativeGem < StandardError
        def initialize(gem_name, version)
          gem_version_msg = indented_code("gem '#{gem_name}', '#{version}'")
          super("by adding the following to your Gemfile:\n#{gem_version_msg}\n\nThis can go into the same :development group if (you are using one):\n" <<
                indented_code("group :development do\n\tgem 'rails-dev-boost', :github => 'thedarkone/rails-dev-boost'#{gem_version_msg}\nend\n"))
        end
        
        private
        def indented_code(msg)
          "\n\t" << msg.gsub("\n", "\n\t")
        end
      end
      
      extend self
      attr_reader :gem_load_error
      
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
      rescue MissingNativeGem => e
        @gem_load_error ||= e.message
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
        
        class << self
          def usable?
            gem_check! if platform_match?
          end
          
          private
          def platform_match?
            require 'rbconfig'
            RbConfig::CONFIG['target_os'] =~ self::TARGET_OS_REGEX
          end
          
          def gem_check!
            defined?(@gem_loaded) ? @gem_loaded : @gem_loaded = load_gem!
          end
          
          def load_gem!
            gem(self::GEM_NAME, self::GEM_VERSION)
            require(self::GEM_NAME)
            true
          rescue Gem::LoadError
            raise MissingNativeGem.new(self::GEM_NAME, self::GEM_VERSION)
          end
        end
      end

      class Darwin < Base
        TARGET_OS_REGEX = /darwin(1.+)?$/i
        GEM_NAME        = 'rb-fsevent'
        GEM_VERSION     = '>= 0.9.1'
        
        private
        def create_watcher
          FSEvent.new
        end
      end

      # Errors, comments and other gotchas taken from Listen gem (https://github.com/guard/listen)
      class Linux < Base
        TARGET_OS_REGEX = /linux/i
        GEM_NAME        = 'rb-inotify'
        GEM_VERSION     = '>= 0.8.8'
        
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
              unless root?(event) || file_event_on_a_dir?(event)
                if File.file?(absolute_name = event.absolute_name)
                  yield [File.dirname(absolute_name)]
                elsif File.directory?(absolute_name)
                  yield [absolute_name]
                end
              end
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
        TARGET_OS_REGEX = /mswin|mingw|cygwin/i
        GEM_NAME        = 'wdm'
        GEM_VERSION     = '>= 0.0.3'
        
        private
        def watch_internal(directories)
          directories.each do |directory|
            begin
              @watcher.watch_recursively(directory) do |change|
                yield [File.dirname(change.path)]
              end
            rescue WDM::InvalidDirectoryError
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

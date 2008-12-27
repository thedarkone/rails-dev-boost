require 'test/unit'
require 'mocha'

require 'stub_environment'
require 'rails_development_boost'
RailsDevelopmentBoost.apply!

class RailsDevelopmentBoostTest < Test::Unit::TestCase
  def test_single_removal
    load_from "single_removal"
    
    assert_same_object_id('A') { reload! }
    assert_different_object_id('A') { reload! { update("a.rb") } }
    assert_different_object_id('A') { reload! { update("a.rb") } }
    assert_same_object_id('A') { reload! }
    
    assert_same_object_id('B') do
      assert_different_object_id('A') do
        reload! do
          update("a.rb")
        end
      end
    end
  end
  
  def test_subclass_update_cascade
    load_from "subclass"
    
    assert_different_object_id 'A', 'B' do
      assert_same_object_id 'C' do
        reload! do
          update("a.rb")
        end
      end
    end
  end
  
  def test_nested_constant_update_cascade
    load_from "deep_nesting"
    
    assert_different_object_id 'A::B::C::D', 'A::B::C', 'A::B', 'A' do
      reload! do
        update("a.rb")
      end
    end
  end
  
  def test_mixin_update_cascade
    load_from "mixins"
    
    assert_different_object_id 'Mixin', 'Client' do
      reload! do
        update("mixin.rb")
      end
    end
    
    assert Client.public_method_defined?('from_mixin') # sanity check
    
    # Simulate a change in the mixin file
    reload! do
      update("mixin.rb")
    end
    Deps.load_paths.unshift("#{@constant_dir}/update")
    
    assert !Client.public_method_defined?('from_mixin')
    assert Client.public_method_defined?('from_mixin_update')
  end
  
  def test_prevention_of_removal_cycle
    load_from "double_removal"
    
    # Failure of this test = SystemStackError: stack level too deep
    assert_different_object_id 'Ns::M', 'Ns::C', 'Ns' do
      reload! do
        update("ns/m.rb")
      end
    end
  end
  
  def test_nested_mixins
    load_from "nested_mixins"
    
    assert_different_object_id 'Ma::Mb::Mc', 'Ma::Mb', 'Ma' do
      assert_different_object_id 'Oa::Ob::Oc', 'Oa::Ob', 'Oa' do
        assert_same_object_id 'B::C' do
          reload! do
            update("ma/mb/mc.rb")
          end
        end
      end
    end
  end
  
  def test_singleton_mixins
    load_from "singleton_mixins"
    
    assert_different_object_id 'A' do
      reload! do
        update("b.rb")
      end
    end
    assert_same_object_id 'B' do
      reload! do
        update("a.rb")
      end
    end
  end
  
  def test_consistency_of_activerecord_registry
    load_from "active_record"
    
    fetch_registered_ar_subclasses = lambda do
      ActiveRecord::Base.instance_eval { subclasses }.sort_by(&:name)
    end
    
    # Load initial version of the models
    assert_equal [Comment, Message, Other, Post], fetch_registered_ar_subclasses[]
    
    # AR::Base subclass tree is updated
    assert_different_object_id 'Message', 'Post', 'Comment' do
      assert_same_object_id 'Other' do
        reload! do
          update("message.rb")
        end
      end
    end
    assert_equal [Comment, Message, Other, Post], fetch_registered_ar_subclasses[]
    
    # Create initial references to reflection classes
    assert_equal Comment, Post.new.comments.new.class
    
    # Reflections are updated
    assert_same_object_id 'Post' do
      assert_different_object_id 'Comment' do
        reload! do
          update("comment.rb")
        end
      end
    end
    assert_equal Comment, Post.new.comments.new.class
  end
  
protected

  CONSTANT_DIR    = "#{File.dirname(__FILE__)}/constants".freeze
  CONSTANT_FILES  = Dir.chdir(CONSTANT_DIR) { Dir.glob("**/*.rb") }.freeze
  
  Deps = ActiveSupport::Dependencies
  
  def setup
    # Cleanup
    clean_up! "setup"
    @constant_dir = CONSTANT_DIR
    
    # Configuration
    Deps.load_paths = [CONSTANT_DIR]
    Deps.logger = Logger.new(STDERR)
    Deps.log_activity = false
    
    # Stub mtimes
    CONSTANT_FILES.each { |file| stub_mtime(file) }
  end
  
  def teardown
    clean_up! "teardown"
  end
  
private

  def load_from(root)
    @constant_dir = "#{CONSTANT_DIR}/#{root}"
    Deps.load_paths = [@constant_dir]
  end

  def update(path)
    stub_mtime(path, File.mtime("#{@constant_dir}/#{path}") + 1)
  end
  
  def stub_mtime(path, time=1)
    File.stubs(:mtime).with("#{@constant_dir}/#{path}").returns time
  end
  
  def reload!
    ActionController::Dispatcher.new.cleanup_application
    yield if block_given?
    ActionController::Dispatcher.new.reload_application
  end
  
  def clean_up!(stage)
    message = "#{stage} dependency cleanup of <#{@method_name}> failed"
    
    Deps.clear
    Deps.history.clear
    
    assert_equal([], Deps.constants_being_removed, message)
    assert_equal([], Deps.module_cache, message)
    assert_equal(Set.new, Deps.loaded, message)
    assert_equal({}, Deps.file_map, message)
    assert_equal([], Deps.autoloaded_constants, message)
  end
  
  def assert_same_object_id(*expressions, &block)
    each_object_id_diff(block, expressions) do |expr, before, after|
      assert_equal(before, after, "<#{expr}.object_id> has changed")
    end
  end
  
  def assert_different_object_id(*expressions, &block)
    each_object_id_diff(block, expressions) do |expr, before, after|
      assert_not_equal(before, after, "<#{expr}.object_id> has remained the same")
    end
  end
  
  def each_object_id_diff(alter, expressions)
    ids_before = expressions.map { |expr| [expr, eval("#{expr}.object_id")] }
    alter.call
    ids_before.each do |expr, before|
      after = eval("#{expr}.object_id")
      yield expr, before, after
    end
  end
end

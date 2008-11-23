require 'test/unit'
require 'mocha'

require 'stub_environment'
require 'rails_development_boost'
RailsDevelopmentBoost.apply!

class RailsDevelopmentBoostTest < Test::Unit::TestCase
  def test_constant_update
    assert_same_object_id('A') { reload! }
    assert_different_object_id('A') { reload! { update("a.rb") } }
    assert_different_object_id('A') { reload! { update("a.rb") } }
    assert_same_object_id('A') { reload! }
    
    assert_same_object_id('D') do
      assert_different_object_id('A') do
        reload! do
          update("a.rb")
        end
      end
    end
  end
  
  def test_subclass_update_cascade
    assert_different_object_id 'A', 'B' do
      reload! do
        update("a.rb")
      end
    end
  end
  
  def test_nested_constants_update_cascade
    assert_different_object_id 'A', 'A::C' do
      reload! do
        update("a.rb")
      end
    end
  end
  
  def test_mixin_update_cascade
    assert_different_object_id 'Mixin', 'Client' do
      reload! do
        update("mixin.rb")
      end
    end
    
    assert Client.public_method_defined?('from_mixin') # sanity check
    reload! do
      update("mixin.rb")
    end
    Deps.load_paths.unshift("#{CONSTANT_DIR}/update")
    assert !Client.public_method_defined?('from_mixin')
    assert Client.public_method_defined?('from_mixin_update')
  end
  
  def test_prevention_of_removal_cycle
    assert_different_object_id 'Mut::M', 'Mut::C', 'Mut' do
      reload! do
        update("mut/m.rb")
      end
    end
  end
  
private

  Deps = ActiveSupport::Dependencies
  
  CONSTANT_DIR    = File.dirname(__FILE__) + '/constants'
  CONSTANT_FILES  = Dir.chdir(CONSTANT_DIR) { Dir.glob("**/*.rb") }
  CONSTANTS       = %w( A B A::C D Mixin Client Mut Mut::M Mut::C )
  
  def setup
    # Configuration
    Deps.load_paths = [CONSTANT_DIR]
    Deps.logger = Logger.new(STDERR)
    Deps.log_activity = false

    # Cleanup
    CONSTANTS.each do |const|
      if Deps.qualified_const_defined?(const)
        Deps.instance_eval { remove_constant(const) }
      end
    end
    Deps.history.clear
    
    # Sanity checks
    assert_equal([], Deps.constants_being_removed)
    assert_equal([], Deps.module_cache)
    assert_equal(Set.new, Deps.loaded)
    assert_equal({}, Deps.file_map)
    assert_equal([], Deps.autoloaded_constants)
    
    # Stub mtimes
    CONSTANT_FILES.each { |file| stub_mtime(file) }
  end
  
private

  def update(path)
    stub_mtime(path, File.mtime("#{CONSTANT_DIR}/#{path}") + 1)
  end
  
  def stub_mtime(path, time=1)
    path = "#{CONSTANT_DIR}/#{path}"
    File.stubs(:exist?).with(path).returns true
    File.stubs(:mtime).with(path).returns time
  end
  
  def reload!
    ActionController::Dispatcher.new.cleanup_application
    yield if block_given?
    ActionController::Dispatcher.new.reload_application
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
    ids_before = expressions.map { |expr| [expr.dup, eval("#{expr.dup}.object_id")].dup }
    alter.call
    ids_before.each do |expr, before|
      after = eval("#{expr}.object_id")
      yield expr, before, after
    end
  end
end

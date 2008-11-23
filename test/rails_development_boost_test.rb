require 'test/unit'
require 'mocha'

require 'fileutils'
require 'stub_environment'

require 'rails_development_boost'
RailsDevelopmentBoost.apply!

class RailsDevelopmentBoostTest < Test::Unit::TestCase
  Deps = ActiveSupport::Dependencies
  
  CONSTANTS = %w( A
                  B
                  A::C
                  D
                  Mixin
                  Client )
  
  def setup
    Deps.load_paths = [constant_dir]

    CONSTANTS.each do |const|
      if Deps.qualified_const_defined?(const)
        Deps.instance_eval { remove_constant(const) }
      end
    end
    Deps.history.clear
    
    assert_equal([], Deps.constants_being_removed)
    assert_equal([], Deps.module_cache)
    assert_equal(Set.new, Deps.loaded)
    assert_equal({}, Deps.file_map)
    assert_equal([], Deps.autoloaded_constants)
  end
  
  def test_constant_update
    assert_same_object_id 'A' do
      reload!
    end
    
    assert_different_object_id 'A' do
      reload! do
        update("a.rb")
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
    
    assert Client.instance_methods.include?('from_mixin') # sanity check
    Deps.load_paths = ["#{constant_dir}/update"]
    reload! do
      update("mixin.rb")
    end
    assert !Client.instance_methods.include?('from_mixin')
    assert Client.instance_methods.include?('from_mixin_update')
  end
  
private

  def update(path)
    path = "#{constant_dir}/#{path}"
    assert File.file?(path), "attempted to touch a missing file: #{path}"
    FileUtils.touch(path)
  end

  def constant_dir
    File.dirname(__FILE__) + '/constants'
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
    ids_before = expressions.map { |expr| [expr, eval("#{expr}.object_id")] }
    alter.call
    ids_before.each do |expr, before|
      after = eval("#{expr}.object_id")
      yield expr, before, after
    end
  end
end

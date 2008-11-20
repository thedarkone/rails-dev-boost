require 'test/unit'
require 'mocha'

require 'active_support'
require 'selective_constant_unload'

class SelectiveConstantUnload::DependenciesPatchTest < Test::Unit::TestCase
  include SelectiveConstantUnload
  
  def new_dependencies
    yield Object.new.extend(SelectiveConstantUnload::DependenciesPatch)
  end
  
# private

  def test_remove_tracks_of_unloaded_const
    File.stubs :mtime
    
    new_dependencies do |deps|
      map = { 'source.rb' => LoadedFile.new('source.rb', ["A", "B"]) }
      deps.stubs(:file_map).returns map
      deps.stubs(:autoloaded_constants).returns ["A", "B", "C"]
      deps.stubs(:loaded).returns ["source.rb", "other.rb"]
      
      deps.instance_eval { remove_tracks_of_unloaded_const("A") }
      assert_equal(["B", "C"], deps.autoloaded_constants)
      assert_equal(["B"], deps.file_map['source.rb'].constants)
      assert_equal(["source.rb", "other.rb"], deps.loaded)
      
      deps.instance_eval { remove_tracks_of_unloaded_const("B") }
      assert_equal(["C"], deps.autoloaded_constants)
      assert_equal({}, deps.file_map)
      assert_equal(["other.rb"], deps.loaded)
    end
  end
end

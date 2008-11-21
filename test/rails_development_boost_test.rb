require 'test/unit'
require 'mocha'

require 'active_support'
require 'rails_development_boost'

class RailsDevelopmentBoost::DependenciesPatchTest < Test::Unit::TestCase
  include RailsDevelopmentBoost
  
# private

  def test_remove_tracks_of_unloaded_const
    deps = Object.new.extend(RailsDevelopmentBoost::DependenciesPatch)
    
    File.stubs :mtime
    
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

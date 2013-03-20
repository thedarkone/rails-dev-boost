# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{rails-dev-boost}
  s.version = "0.2.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Roman Le Negrate", "thedarkone"]
  s.description = %q{Make your Rails app 10 times faster in development mode}
  s.email = %q{roman.lenegrate@gmail.com}
  s.extra_rdoc_files = ['LICENSE', 'README.markdown']
  s.files = Dir.glob('{lib,test}/**/*') + ['LICENSE', 'README.markdown', 'VERSION']
  s.homepage = %q{http://github.com/thedarkone/rails-dev-boost}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.summary = %q{Speeds up Rails development mode}
  s.test_files = Dir.glob('test/**/*')
  
  s.add_dependency 'railties', '>= 3.0'
  s.add_dependency 'listen',   '>= 0.5'

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end


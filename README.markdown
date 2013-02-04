# Fix slow Rails development mode via `rails-dev-boost`

Make your Rails app 10 times faster in development mode (see FAQ below for more details).

Alternative to Josh Goebel's [`rails_dev_mode_performance`](https://github.com/yyyc514/rails_dev_mode_performance) plugin.

Alternative to Robert Pankowecki's [`active_reload`](https://github.com/paneq/active_reload) gem.

## Branches

If you are using **Rails 3**: [`rails-dev-boost/master`](http://github.com/thedarkone/rails-dev-boost/tree/master) branch.

If you are using **Rails 2.3**: [`rails-dev-boost/rails-2-3`](http://github.com/thedarkone/rails-dev-boost/tree/rails-2-3) branch.

If you are using **Rails 2.2**: [`rails-dev-boost/rails-2-2`](http://github.com/thedarkone/rails-dev-boost/tree/rails-2-2) branch.

If you are using **Rails 2.1** or **Rails 2.0** or **anything older**: you are out of luck.

## Problems

If your app doesn't work with `rails-dev-boost`:

 * make sure you are not keeping "class-level" references to reloadable constants (see "Known limitations" section below)
 * otherwise **please open an [issue](https://github.com/thedarkone/rails-dev-boost/issues)**!
 
I'm very interested in making the plugin as robust as possible and will work with you on fixing any issues.

### Debug mode

There is built-in debug mode in `rails-dev-boost` that can be enabled by putting this line a Rails initializer file:

    RailsDevelopmentBoost.debug! if defined?(RailsDevelopmentBoost)

After restarting your server `rails-dev-boost` will start to spewing detailed tracing information about its actions into your `development.log` file.

## Background

Why create a similar plugin? Because I couldn't get Josh Goebel's to work in my projects. His attempts to keep templates cached in a way that fails with recent versions of Rails. Also, removing the faulty chunk of code revealed another issue: it stats source files that may not exist, without trying to find their real path beforehand. That would be fixable is the code wasn't such a mess (no offense).

I needed better performance in development mode right away, so here is an alternative implementation.

## Usage

### Rails 3

Usage through `Gemfile`:

```ruby
group :development do
  gem 'rails-dev-boost', :git => 'git://github.com/thedarkone/rails-dev-boost.git'
end
```

Installing as a plugin:

    script/rails plugin install git://github.com/thedarkone/rails-dev-boost

### Rails 2.3 and older

    script/plugin install git://github.com/thedarkone/rails-dev-boost -r rails-2-3

When the server is started in *development* mode, the special unloading mechanism takes over.

It can also be used in combination with [RailsTestServing](https://github.com/Roman2K/rails-test-serving) for even faster test runs by forcefully enabling it in test mode. To do so, add the following in `config/environments/test.rb`:

```ruby
def config.soft_reload() true end if RailsTestServing.active?
```

## Known limitations

The only code `rails-dev-boost` is unable to handle are "class-level" reloadable constant inter-references ("reloadable" constants are classes/modules that are automatically reloaded in development mode: models, helpers, controllers etc.).

### Class-level reference examples

```ruby
# app/models/article.rb
class Article
end

# app/models/blog.rb
class Blog
  ARTICLE_CLASS = Article # <- stores class-level reference
  @article = Article # <- stores class-level reference
  @@article = Article # <- stores class-level reference

  MODELS_ARRAY = []
  MODELS_ARRAY << Article # <- stores class-level reference

  MODELS_CACHE = {}
  MODELS_CACHE['Article'] ||= Article # <- stores class-level reference

  class << self
    attr_accessor :article_klass
  end

  self.article_klass = Article # <- stores class-level reference

  def self.article_klass
    @article_klass ||= Article # <- stores class-level reference
  end

  def self.article_klass2
    @article_klass ||= 'Article'.constantize # <- stores class-level reference
  end

  def self.find_article_klass
    const_set(:ARTICLE_CLASS, Article) # <- stores class-level reference
  end

  def self.all_articles
    # caching object instances is as bad, because each object references its own class
    @all_articles ||= [Article.new, Article.new] # <- stores class-level reference
  end

  article_kls_ref = Article
  GET_ARTICLE_PROC = Proc.new { article_kls_ref } # <- stores class-level reference via closure
end
```

### What goes wrong

Using the example files from above, here's the output from a Rails console:

    irb(main):001:0> Article
    => Article
    irb(main):002:0> Blog
    => Blog
    irb(main):003:0> Blog.object_id
    => 2182137540
    irb(main):004:0> Article.object_id
    => 2182186060
    irb(main):005:0> Blog::ARTICLE_CLASS.object_id
    => 2182186060
    irb(main):006:0> Blog.all_articles.first.class.object_id
    => 2182186060

Now imagine that we change the `app/models/article.rb` and add a new method:

```ruby
# app/models/article.rb
class Article
  def say_hello
    puts "Hello world!"
  end
end
```

Back in console, trigger an app reload:

    irb(main):007:0> reload!
    Reloading...
    => true

When `app/models/article.rb` file is saved `rails-dev-boost` detects the change and calls `ActiveSupport::Dependencies.remove_constant('Article')` this unloads the `Article` constant. At this point `Article` becomes undefined and `Object.const_defined?('Article')` returns `false`.

    irb(main):008:0> Object.const_defined?('Article')
    => false

However all of the `Blog`'s references to the `Article` class are still valid, so doing something like `Blog::ARTICLE_CLASS.new` will not result into an error:

    irb(main):009:0> Blog::ARTICLE_CLASS.new
    => #<Article:0x10415b3a0>
    irb(main):010:0> Blog::ARTICLE_CLASS.object_id
    => 2182186060
    irb(main):011:0> Object.const_defined?('Article')
    => false
    
Now lets try calling the newly added method:

    irb(main):012:0> Blog::ARTICLE_CLASS.new.say_hello
    NoMethodError: undefined method `say_hello' for #<Article:0x104143430>
    	from (irb):12

As can be seen the new method is nowhere to be found. Lets see if this can be fixed by using the `Article` const directly:

    irb(main):013:0> Article.new.say_hello
    Hello world!
    => nil

Yay, it works! Lets try `Blog::ARTICLE_CLASS` again:

    irb(main):014:0> Blog::ARTICLE_CLASS.new.say_hello
    NoMethodError: undefined method `say_hello' for #<Article:0x1040b77f0>
    	from (irb):14

What is happening? When we use the `Article` const directly, since it is undefined Rails does its magic - intercepts the exception and `load`s the `app/models/article.rb`. This creates a brand new `Article` class with the new `object_id` and stuff.

    irb(main):015:0> Article.object_id
    => 2181443620
    irb(main):016:0> Blog::ARTICLE_CLASS.object_id
    => 2182186060
    irb(main):017:0> Article != Blog::ARTICLE_CLASS
    => true
    irb(main):018:0> Article.public_method_defined?(:say_hello)
    => true
    irb(main):019:0> Blog::ARTICLE_CLASS.public_method_defined?(:say_hello)
    => false

Now we've ended up with 2 distinct `Article` classes. To fix the situation we can force `blog.rb` to be reloaded:

    irb(main):020:0> FileUtils.touch(Rails.root.join('app/models/blog.rb'))
    => ["mongo-boost/app/models/blog.rb"]
    irb(main):021:0> reload!
    Reloading...
    => true
    irb(main):022:0> Blog.object_id
    => 2180872580
    irb(main):023:0> Article.object_id
    => 2181443620
    irb(main):024:0> Blog::ARTICLE_CLASS.object_id
    => 2181443620
    irb(main):025:0> Article == Blog::ARTICLE_CLASS
    => true
    irb(main):026:0> Blog::ARTICLE_CLASS.public_method_defined?(:say_hello)
    => true
    irb(main):027:0> Blog::ARTICLE_CLASS.new.say_hello
    Hello world!
    => nil
    
### The fix

#### Code refactor

The best solution is to avoid class-level references at all. A typical bad code looking like this:

```ruby
# app/models/article.rb
class Article < ActiveRecord::Base
end

# app/models/blog.rb
class Blog < ActiveRecord::Base
  def self.all_articles
    @all_articles ||= Article.all
  end
end
```

can easily be rewritten like this:

```ruby
# app/models/article.rb
class Article < ActiveRecord::Base
  def self.all_articles
    @all_articles ||= all
  end
end

# app/models/blog.rb
class Blog < ActiveRecord::Base
  def self.all_articles
    Article.all_articles
  end
end
```

This way saving `arcticle.rb` will trigger the reload of `@all_articles`.

#### require_dependency

If the code refactor isn't possible, make use of the `ActiveSupport`'s `require_dependency`:

```ruby
#app/models/blog.rb
require_dependency 'article'

class Blog < ActiveRecord::Base
  def self.all_articles
    @all_articles ||= Article.all
  end
  
  def self.authors
    @all_authors ||= begin
      require_dependency 'author' # dynamic require_dependency is also fine
      Author.all
    end
  end
end
```

## Asynchronous mode

By default `rails-dev-boost` now runs in an "async" mode, watching and unloading modified files in a separate thread. This allows for an even faster development mode because there is no longer a need to do a `File.mtime` check of all the `.rb` files at the beginning of the request.

To disable the async mode put the following code in a Rails initializer file (these are found in `config/initializers` directory):
```ruby
RailsDevelopmentBoost.async = false
```

## FAQ

### Q: Since the plugin uses its special "unloading mechanism" won't everything break down?
A: Very unlikely... of course there are some edge cases where you might see some breakage (mainly if you're deviating from the Rails 1 file = 1 class conventions or doing some weird `require`s). This is a 99% solution and the seconds you're wasting waiting for the Rails to spit out a page in the dev mode do add up in the long run.

### Q: How big of a boost is it going to give me?
A: It depends on the size of your app (the bigger it is the bigger your boost is going to be). The speed is then approximately equal to that of production env. plus the time it takes to stat all your app's `*.rb` files (which is surprisingly fast as it is cached by OS). Empty 1 controller 2 views app will become about 4x times faster more complex apps will see huge improvements.

### Q: I'm using an older version of Rails than 2.2, will this work for me?
A: Unfortunately you are on your own right now :(.

### Q: My `Article` model does not pick up changes from the `articles` table.
A: You need to force it to be reloaded (just hit the save button in your editor for `article.rb` file).

### Q: I used `require 'article'` and the `Article` model is not being reloaded.
A: You really shouldn't be using `require` to load your files in the Rails app (if you want them to be automatically reloaded) and let automatic constant loading handle the require for you. You can also use `require_dependency 'article'`, as it goes through the Rails stack.

### Q: I'm using JRuby, is it going to work?
A: I haven't tested the plugin with JRuby, but the plugin does use `ObjectSpace` to do its magic. `ObjectSpace` is AFAIK disabled by default on JRuby.

FAQ added by [thedarkone](http://github.com/thedarkone).

## Credits

Written by [Roman Le Négrate](http://roman.flucti.com) ([contact](mailto:roman.lenegrate@gmail.com)). Released under the MIT-license: see the `LICENSE` file.

# RailsDevelopmentBoost

Make your Rails app 10 times faster in development mode (see FAQ below for more details).

Alternative to Josh Goebel's [`rails_dev_mode_performance`](https://github.com/yyyc514/rails_dev_mode_performance) plugin.

## Branches

If you are using **Rails 3**: [`rails-dev-boost/master`](http://github.com/thedarkone/rails-dev-boost/tree/master) branch.

If you are using **Rails 2.3**: [`rails-dev-boost/rails-2-3`](http://github.com/thedarkone/rails-dev-boost/tree/rails-2-3) branch.

If you are using **Rails 2.2**: [`rails-dev-boost/rails-2-2`](http://github.com/thedarkone/rails-dev-boost/tree/rails-2-2) branch.

If you are using **Rails 2.1** or **Rails 2.0** or **anything older**: you are out of luck.

## Background

Why create a similar plugin? Because I couldn't get Josh Goebel's to work in my projects. His attempts to keep templates cached in a way that fails with recent versions of Rails. Also, removing the faulty chunk of code revealed another issue: it stats source files that may not exist, without trying to find their real path beforehand. That would be fixable is the code wasn't such a mess (no offense).

I needed better performance in development mode right away, so here is an alternative implementation.

## Usage

    script/plugin install git://github.com/thedarkone/rails-dev-boost -r rails-2-3

When the server is started in *development* mode, the special unloading mechanism takes over.

It can also be used in combination with [RailsTestServing](https://github.com/Roman2K/rails-test-serving) for even faster test runs by forcefully enabling it in test mode. To do so, add the following in `config/environments/test.rb`:

    def config.soft_reload() true end if RailsTestServing.active?

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

### Q: I'm using class variables (by class variables I mean "metaclass instance variables") and they are not being reloaded.
A: Class level instance variables are not thread safe and you shouldn't be really using them :). There is generally only one case where they might pose a problem for `rails-dev-boost`:
    
    #app/models/article.rb
    class Article < ActiveRecord::Base
    end
    
    #app/models/blog.rb
    class Blog < ActiveRecord::Base
      def self.all_articles
        @all_articles ||= Article.all
      end
    end

Modifying `article.rb` will not reload `@all_articles` (you would always need to re-save `blog.rb` as well).

The solution is to move class instance variable to its class like this:

    #app/models/article.rb
    class Article < ActiveRecord::Base
      def self.all_articles
        @all_articles ||= all
      end
    end
    
    #app/models/blog.rb
    class Blog < ActiveRecord::Base
      def self.all_articles
        Article.all_articles
      end
    end
    
This way saving `arcticle.rb` will trigger the reload of `@all_articles`.

### Q: I'm using JRuby, is it going to work?
A: I haven't tested the plugin with JRuby, but the plugin does use `ObjectSpace` to do its magic. `ObjectSpace` is AFAIK disabled by default on JRuby.

FAQ added by [thedarkone](http://github.com/thedarkone).

## Credits

Written by [Roman Le Négrate](http://roman.flucti.com) ([contact](mailto:roman.lenegrate@gmail.com)). Released under the MIT-license: see the `LICENSE` file.

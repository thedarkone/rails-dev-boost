if Rails.env.development? || (config.respond_to?(:soft_reload) && config.soft_reload)
  require 'rails_development_boost'
  RailsDevelopmentBoost.apply!
end

if Rails.env.development? || (config.respond_to?(:soft_reload) && config.soft_reload)
  require 'rails_development_boost'
  config.to_prepare do
    RailsDevelopmentBoost.apply!
  end
end

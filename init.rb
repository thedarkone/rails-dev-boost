if Rails.env.development? || (config.respond_to?(:soft_reload) && config.soft_reload)
  if ENV['_'].grep(/rake$/).empty?
    require 'rails_development_boost'
    RailsDevelopmentBoost.apply!
  end
end

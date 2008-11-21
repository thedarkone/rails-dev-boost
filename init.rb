if Rails.env.development?
  require 'rails_development_boost'
  RailsDevelopmentBoost.apply!
end

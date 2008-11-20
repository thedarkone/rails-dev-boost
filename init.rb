if Rails.env.development?
  config.after_initialize do
    require 'selective_constant_unload'
    SelectiveConstantUnload.apply!
  end
end

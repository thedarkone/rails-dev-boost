if Rails.env.development?
  require 'selective_constant_unload'
  SelectiveConstantUnload.apply!
end

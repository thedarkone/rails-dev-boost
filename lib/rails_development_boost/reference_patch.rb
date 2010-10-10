module RailsDevelopmentBoost
  module ReferencePatch
    def self.apply!
      ActiveSupport::Dependencies::Reference.send :include, self
      ActiveSupport::Dependencies::Reference.cattr_reader :constants
    end
    
    def loose
      self.class.constants.delete(@name)
    end
  end
end
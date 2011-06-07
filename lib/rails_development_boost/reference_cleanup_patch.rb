module RailsDevelopmentBoost
  module ReferenceCleanupPatch
    def self.apply!
      Module.send :include, self
      Module.alias_method_chain :remove_const, :reference_cleanup
    end
    
    def remove_const_with_reference_cleanup(const_name)
      ActiveSupport::Dependencies::Reference.loose!(self == Object ? const_name : "#{_mod_name}::#{const_name}")
      ActiveSupport::DescendantsTracker.delete(const_get(const_name))
      remove_const_without_reference_cleanup(const_name)
    end
  end
end
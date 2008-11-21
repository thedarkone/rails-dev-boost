require 'delegate'

module SelectiveConstantUnload
  class FutureReference < SimpleDelegator
    def initialize(const_name)
      super(nil)
      @const_name = const_name
    end
  
  private

    def method_missing(method, *args, &block)
      __setobj__(@const_name.constantize) if __getobj__.nil?
      
      p :future => @constantize, :meth => method
      
      super
    end
  end
end

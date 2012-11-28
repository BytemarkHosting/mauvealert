require 'dm-validations'

module DataMapper
  module Validations
    #
    # This only performs validations if the object being saved is dirty.
    #
    def save_self(*)
      # 
      # short-circuit if the resource is not dirty
      #
      if dirty_self? && Validations::Context.any? && !valid?(model.validators.current_context)
        false
      else
        super
      end
    end
  end
end



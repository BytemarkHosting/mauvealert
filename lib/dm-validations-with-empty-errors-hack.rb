require 'dm-validations'

module DataMapper
  module Validations
    #
    # Rewrite save method to save without validations, if the validations failed, but give no reason.
    #
    # @api private
    def save_self(*)
      if Validations::Context.any? && !valid?(model.validators.current_context)
        #
        # Don't do anything unusual if there is no logger available.
        #
        return false unless self.respond_to?("logger")

        if self.errors.empty?
          logger.warn "Forced to save #{self.inspect} without validations due to #{self.errors.inspect}."
          super
        else
          false
        end
      else
        super
      end
    end
  end
end




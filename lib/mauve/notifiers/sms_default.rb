module Mauve
  module Notifiers
    module Sms
      class Default
        def initialize(*args)
          raise ArgumentError.new("No default SMS provider, you must use the provider command to select one")
        end
      end
    end
  end
end


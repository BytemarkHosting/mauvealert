require 'mauve/notifiers'
require 'mauve/configuration_builder'

module Mauve
  module ConfigurationBuilders
    class NotificationMethod < ObjectBuilder

      #
      # Set up the notification.  Missing notifiers are caught via NameError in
      # the ObjectBuilder#parse method.
      #
      # @param [String] name Name of the notifier
      # 
      def builder_setup(name)
        notifiers_base = Mauve::Notifiers

        @notifier_type = notifiers_base.const_get(name.capitalize)

        @name = name
        provider("Default")
      end

      # This allows use of multiple notification providers, e.g. in the case of
      # SMS.
      #
      # Missing providers are caught via NameError in the ObjectBuilder#parse
      # method.
      #
      def provider(name)
        @provider_class = @notifier_type.const_get(name)
      end
      
      # Returns the result for this builder, depending on the configuration
      #
      def result
        @result ||= @provider_class.new(@name)
      end

      def debug!
        result.extend(Mauve::Notifiers::Debug)
      end
     
      # This catches all methods available for a provider, as needed.
      #
      # Missing methods / bad arguments etc. are caught in the
      # ObjectBuilder#parse method, via NoMethodError.
      #
      def method_missing(name, value=nil)
        if value
          result.send("#{name}=".to_sym, value)
        else
          result.send(name.to_sym)
        end
      end
    end
  end

  #
  # Add notification_method to our top-level config builder
  #
  class ConfigurationBuilder < ObjectBuilder
    is_builder "notification_method", ConfigurationBuilders::NotificationMethod

    # Method called after a notification method has been created to check for duplicate names.
    #
    # @raise [BuildException] when a duplicate notification method is found.
    def created_notification_method(notification_method)
      name = notification_method.name
      raise BuildException.new("Duplicate notification '#{name}'") if @result.notification_methods[name]
      @result.notification_methods[name] = notification_method
    end

  end

end


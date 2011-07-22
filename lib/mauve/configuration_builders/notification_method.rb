require 'mauve/notifiers'
require 'mauve/configuration_builder'

# encoding: UTF-8
module Mauve
  module ConfigurationBuilders
    class NotificationMethod < ObjectBuilder

      def builder_setup(name)
        @notification_type = name.capitalize
        @name = name
        provider("Default")
      end

      def provider(name)
        notifiers_base = Mauve::Notifiers
        notifiers_type = notifiers_base.const_get(@notification_type)
        @provider_class = notifiers_type.const_get(name)
      end
      
      def result
        @result ||= @provider_class.new(@name)
      end
      
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

    def created_notification_method(notification_method)
      name = notification_method.name
      raise BuildException.new("Duplicate notification '#{name}'") if @result.notification_methods[name]
      @result.notification_methods[name] = notification_method
    end

  end

end


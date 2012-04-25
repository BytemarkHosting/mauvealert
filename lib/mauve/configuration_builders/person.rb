# encoding: UTF-8
require 'object_builder'
require 'mauve/person'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders/alert_group'

module Mauve
  module ConfigurationBuilders

    class Person < ObjectBuilder

      def builder_setup(username)
        @result = Mauve::Person.new(username)
      end

      is_builder "notification", Notification

      is_block_attribute "urgent"
      is_block_attribute "normal"
      is_block_attribute "low"

      is_attribute "password"
      is_attribute "sms"
      is_attribute "email"
      is_attribute "xmpp"

      is_flag_attribute "notify_when_on_holiday!"
      is_flag_attribute "notify_when_off_sick!"
     
      # Sets the block for all levels of alert
      #
      # @param [Block] block 
      def all(&block); urgent(&block); normal(&block); low(&block); end

      #
      # Notify is a shortcut for "notification"
      #
      def notify(&block)
        notification(@result, &block)
      end

      def created_notification(notification)
        @result.notifications ||= []
        @result.notifications << notification
      end

      # Notification suppression hash
      #
      # @param [Hash] h
      def suppress_notifications_after(h)
        raise ArgumentError.new("notification_threshold must be specified as e.g. (10 => 1.minute)") unless h.kind_of?(Hash)

        h.each do |k,v|
          raise ArgumentError.new("notification_threshold must be specified as e.g. (10 => 1.minute)") unless k.is_a?(Integer) and v.is_a?(Integer)

          @result.notification_thresholds[v] = Array.new(k)
        end
      end

    end
  end

  class ConfigurationBuilder < ObjectBuilder

    is_builder "person", ConfigurationBuilders::Person

    # Method called once a person has been created to check for duplicate names
    #
    # @param [Mauve::Person] person
    # @raise [ArgumentError] if a person has already been declared.
    #
    def created_person(person)
      name = person.username
      raise ArgumentError.new("Duplicate person '#{name}'") if @result.people[name]
      #
      # Add a default notification threshold
      #
      person.notification_thresholds[60] = Array.new(10) if person.notification_thresholds.empty?
      @result.people[person.username] = person
    end

  end
end

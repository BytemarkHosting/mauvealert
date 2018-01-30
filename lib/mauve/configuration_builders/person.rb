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
      is_attribute "hipchat"
      is_attribute "pushover"

      is_flag_attribute "notify_when_on_holiday"
      is_flag_attribute "notify_when_off_sick"

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

        h.each do |number_of_alerts,in_period|
          raise ArgumentError.new("notification_threshold must be specified as e.g. (10 => 1.minute)") unless number_of_alerts.is_a?(Integer) and in_period.is_a?(Integer)

          @result.suppress_notifications_after[in_period] = number_of_alerts
          # History.all(
          # :limit => number_of_alerts,
          # :order => :created_at.desc,
          # :type => "notification",
          # :event.like => '% succeeded')
        end
      end

      #
      #
      def notify_when_on_holday!
        result.notify_when_on_holiday = true
      end

      def notify_when_off_sick!
        result.notify_when_off_sick = true
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
      person.suppress_notifications_after[600] = 5 if person.suppress_notifications_after.empty?

      #
      # Add a default notify clause
      #
      if person.notifications.empty?
        default_notification = Notification.new(person)
        default_notification.every = 30.minutes
        default_notification.during = Proc.new { working_hours? }
        person.notifications << default_notification
      end

      #
      # Set up some default notify levels.
      #
      if person.urgent.nil? and person.normal.nil? and person.low.nil?
        person.urgent = Proc.new { sms ; xmpp ; email }
        person.normal = Proc.new { xmpp ; email }
        person.low    = Proc.new { email }
      end

      @result.people[person.username] = person
    end

  end
end

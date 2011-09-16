# encoding: UTF-8
require 'object_builder'
require 'mauve/notification'
require 'mauve/configuration_builder'
require 'mauve/alert_group'
require 'mauve/notification'

module Mauve
  module ConfigurationBuilders
    #
    # This corresponds to a new "notify" clause an the alert_group config.
    #
    class Notification < ObjectBuilder

      # Sets up the notification
      # 
      # @param [Array] who List of usernames or people_lists to notify
      # @raise [ArgumentError] if a username doesn't exist.
      #
      # @return [Mauve::Notification] New notification instance.
      def builder_setup(*who)
        who = who.map do |username|
          #raise BuildException.new("You haven't declared who #{username} is") unless
          #  @context.people[username]
          #@context.people[username]
          if @context.people[username]
            @context.people[username]
          elsif @context.people_lists[username]
            @context.people_lists[username]
          else
            raise ArgumentError.new("You have not declared who #{username} is")
          end
        end
        @result = Mauve::Notification.new(who, @context.last_alert_group.level)
      end
      
      is_attribute "every"
      is_block_attribute "during"
    end

    # This corresponds to a new alert_group clause
    #
    class AlertGroup < ObjectBuilder

      # Sets up the alert group, and sets the last_alert_group context.
      # 
      # @param [String] name Name of the new alert group
      #
      # @return [Mauve::AlertGroup] New alert group instance
      def builder_setup(name="anonymous_name")
        @result = Mauve::AlertGroup.new(name)
        @context.last_alert_group = @result
      end

      is_block_attribute "includes"
      is_attribute "acknowledgement_time"
      is_attribute "level"
      is_builder "notify", Mauve::ConfigurationBuilders::Notification

      # Method called after the notify clause has been sorted.  Adds new
      # notification clause to the result.
      #
      # @param [Mauve::Notification] notification
      #
      def created_notify(notification)
        @result.notifications ||= []
        @result.notifications << notification
      end

    end

  end

  # These constants define the levels available for alert groups.
  #
  # This should live in AlertGroup but can't due to
  # http://briancarper.net/blog/ruby-instance_eval_constant_scoping_broken
  #
  module AlertGroupConstants
    # Urgent level
    URGENT = :urgent
    # Normal level
    NORMAL = :normal
    # Low level
    LOW    = :low
  end


  class ConfigurationBuilder < ObjectBuilder

    include AlertGroupConstants

    is_builder "alert_group", ConfigurationBuilders::AlertGroup

    # Called after an alert group is created.  Checks to make sure that no more than one alert group shares a name.
    #
    # @param [Mauve::AlertGroup] alert_group The new AlertGroup
    # @raise [ArgumentError] if an AlertGroup with the same name already exists.
    #
    def created_alert_group(alert_group)
      name = alert_group.name
      raise ArgumentError.new("Duplicate alert_group '#{name}'") unless @result.alert_groups.select { |g| g.name == name }.empty?
      @result.alert_groups << alert_group
    end

  end

end

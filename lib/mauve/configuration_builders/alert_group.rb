# encoding: UTF-8
require 'object_builder'
require 'mauve/notification'
require 'mauve/configuration_builder'
require 'mauve/alert_group'
require 'mauve/notification'

module Mauve
  module ConfigurationBuilders

    class Notification < ObjectBuilder

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
          raise BuildException.new("You have not declared who #{username} is")
        end
      end
      @result = Mauve::Notification.new(who, @context.last_alert_group.level)
    end

    is_attribute "every"
    is_block_attribute "during"
    ##is_attribute "hours_in_day"
    ##is_attribute "unacknowledged"
  end

  class AlertGroup < ObjectBuilder

    def builder_setup(name=anonymous_name)
      @result = Mauve::AlertGroup.new(name)
      @context.last_alert_group = @result
    end

    is_block_attribute "includes"
    is_attribute "acknowledgement_time"
    is_attribute "level"

    is_builder "notify", Notification

    def created_notify(notification)
      @result.notifications ||= []
      @result.notifications << notification
    end

  end

  end

  # this should live in AlertGroup but can't due to
  # http://briancarper.net/blog/ruby-instance_eval_constant_scoping_broken
  #
  module AlertGroupConstants
    URGENT = :urgent
    NORMAL = :normal
    LOW    = :low
  end


  class ConfigurationBuilder < ObjectBuilder

    include AlertGroupConstants

    is_builder "alert_group", ConfigurationBuilders::AlertGroup

    def created_alert_group(alert_group)
      name = alert_group.name
      raise BuildException.new("Duplicate alert_group '#{name}'") unless @result.alert_groups.select { |g| g.name == name }.empty?
      @result.alert_groups << alert_group
    end

  end

end

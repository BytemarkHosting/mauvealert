# encoding: UTF-8
require 'object_builder'
require 'mauve/people_list'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders/alert_group'

module Mauve
  module ConfigurationBuilders

    class PeopleList < ObjectBuilder

     is_builder "notification", ConfigurationBuilders::Notification

      def builder_setup(label, *list)
        @result = Mauve::PeopleList.new(label)
        @result += list
        @result
      end

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

    end
  end

  class ConfigurationBuilder < ObjectBuilder

    is_builder "people_list", ConfigurationBuilders::PeopleList

    # Method called once a people_list has been created to check for duplicate labels
    #
    # @param [Mauve::PeopleList] people_list
    #
    def created_people_list(people_list)
      name = people_list.username
      raise ArgumentError.new("Duplicate person '#{name}'") if @result.people[name]
      @result.people[name] = people_list
    end
  end
end

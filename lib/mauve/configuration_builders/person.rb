# encoding: UTF-8
require 'object_builder'
require 'mauve/person'
require 'mauve/configuration_builder'

module Mauve
  module ConfigurationBuilders

    class Person < ObjectBuilder

      def builder_setup(username)
        @result = Mauve::Person.new(username)
      end

      is_block_attribute "urgent"
      is_block_attribute "normal"
      is_block_attribute "low"
      
      def all(&block); urgent(&block); normal(&block); low(&block); end

      def password (pwd)
        @result.password = pwd.to_s
      end

      def holiday_url (url)
        @result.holiday_url = url.to_s
      end
     
      def email(e)
        @result.email = e.to_s
      end

      def xmpp(x)
        @result.xmpp = x.to_s
      end
      
      def sms(x)
        @result.sms = x.to_s
      end
   
      def suppress_notifications_after(h)
        raise ArgumentError.new("notification_threshold must be specified as e.g. (10 => 1.minute)") unless
          h.kind_of?(Hash) && h.keys[0].kind_of?(Integer) && h.values[0].kind_of?(Integer)

        @result.notification_thresholds[h.values[0]] = Array.new(h.keys[0])
      end
    end
  end

  class ConfigurationBuilder < ObjectBuilder

    is_builder "person", ConfigurationBuilders::Person

    def created_person(person)
      name = person.username
      raise BuildException.new("Duplicate person '#{name}'") if @result.people[name]
      #
      # Add a default notification threshold
      #
      person.notification_thresholds[60] = Array.new(10) if person.notification_thresholds.empty?
      @result.people[person.username] = person
    end

  end
end

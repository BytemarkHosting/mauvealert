# encoding: UTF-8
require 'log4r'
require 'mauve/calendar_interface'

module Mauve 

  # Stores a list of name.
  #
  # @author Yann Golanski
  class PeopleList < Struct.new(:label, :list)

    # Default contrustor.
    def initialize (*args)
      super(*args)
    end

    def label
      self[:label]
    end

    alias username label

    def list
      self[:list]
    end

    #
    # Set up the logger
    def logger
      @logger ||=  Log4r::Logger.new self.class
    end

    #
    # Return the array of people
    #
    def people
      list.collect do |name|
        Configuration.current.people.has_key?(name) ? Configuration.current.people[name] : nil
      end.reject{|person| person.nil?}
    end

  end

end

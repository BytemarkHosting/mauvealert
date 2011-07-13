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
      self[:list] || []
    end

    #
    # Set up the logger
    def logger
      @logger ||=  Log4r::Logger.new self.class.to_s
    end

    #
    # Return the array of people
    #
    def people

      l = list.collect do |name|
        Configuration.current.people.has_key?(name) ? Configuration.current.people[name] : nil
      end.reject{|person| person.nil?}
      #
      # Hmm.. no-one in the list?!
      #
      logger.warn "No-one found in the people list for #{self.label}" if l.empty?

      l
    end

  end

end

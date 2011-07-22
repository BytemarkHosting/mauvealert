# encoding: UTF-8
require 'log4r'
require 'mauve/calendar_interface'

module Mauve 

  # Stores a list of name.
  #
  # @author Yann Golanski
  class PeopleList 

    attr_reader :label, :list

    # Default contrustor.
    def initialize(label)
      raise ArgumentError, "people_list label must be a string" unless label.is_a?(String)
      @label = label
      @list  = []
    end

    alias username label

    def +(arr)
      case arr
        when Array
          arr = arr.flatten
        when String
          arr = [arr]
        else
          logger.warn "Not sure what to do with #{arr.inspect} -- converting to string, and continuing"
          arr = [arr.to_s]
      end

      arr.each do |person|
        if @list.include?(person)
          logger.warn "#{person} is already on the #{self.label} list"
        else
          @list << person
        end
      end

      self
    end

    alias add_to_list +

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

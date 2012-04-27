# encoding: UTF-8
require 'log4r'
require 'mauve/calendar_interface'

module Mauve 

  # Stores a list of Mauve::Person
  #
  #
  class PeopleList 

    attr_reader :label, :list, :notifications

    # Create a new list
    #
    # @param [String] label The name of the list
    # @raise [ArgumentError] if the label is not a string
    #
    def initialize(label)
      raise ArgumentError, "people_list label must be a string #{label.inspect}" unless label.is_a?(String)
      @label = label
      @list  = []
      @notifications = []
    end

    alias username label

    # Append an Array or String to a list
    #
    # @param [Array or String] arr
    # @return [Mauve::PeopleList] self
    def +(arr)
      case arr
        when Array
          arr = arr.flatten
        when String
          arr = [arr]
        when Proc
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

    # @return Log4r::Logger
    def logger
      @logger ||=  Log4r::Logger.new self.class.to_s
    end

    # Return the array of people
    #
    # @return [Array]
    def people(at = Time.now)
      l = list.collect do |name|
        name.is_a?(Proc) ? name.call(at) : name 
      end.flatten.compact.uniq.collect do |name|
        Configuration.current.people[name] 
      end.compact

      #
      # Hmm.. no-one in the list?!
      #
      logger.warn "No-one found in the people list for #{self.label}" if l.empty?

      l
    end

  end

end

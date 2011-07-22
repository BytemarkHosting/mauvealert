require 'mauve/source_list'
require 'mauve/people_list'

# Seconds, minutes, hours, days, and weeks... More than that, we 
# really should not need it.
class Integer
  def seconds; self; end
  def minutes; self*60; end
  def hours; self*3600; end
  def days; self*86400; end
  def weeks; self*604800; end
  alias_method :day, :days
  alias_method :hour, :hours
  alias_method :minute, :minutes
  alias_method :week, :weeks
end


module Mauve

  ## Configuration object for Mauve.
  #
  #
  # @TODO Write some more documentation. This is woefully inadequate.
  #
  class Configuration

    class << self
      attr_accessor :current
    end
    
    attr_accessor :server
    attr_accessor :last_alert_group
    attr_reader   :notification_methods
    attr_reader   :people
    attr_reader   :alert_groups
    attr_reader   :people_lists
    attr_reader   :source_lists
 
    def initialize
      @notification_methods = {}
      @people = {}
      @people_lists = Hash.new{|h,k| h[k] = Mauve::PeopleList.new(k)}
      @source_lists = Hash.new{|h,k| h[k] = Mauve::SourceList.new(k)}
      @alert_groups = []
    end
    
  end
end

require 'mauve/source_list'
require 'mauve/people_list'
require 'mauve/mauve_time'

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

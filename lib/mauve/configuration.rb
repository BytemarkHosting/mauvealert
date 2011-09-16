require 'mauve/source_list'
require 'mauve/people_list'
require 'mauve/mauve_time'

module Mauve

  # Configuration object for Mauve.  This is used as the context in
  # Mauve::ConfigurationBuilder.
  #
  class Configuration

    class << self
      # The current configuration
      # @param  [Mauve::Configuration]
      # @return [Mauve::Configuration]
      attr_accessor :current
    end

    # The Server instance
    # @return [Mauve::Server]
    attr_accessor :server

    # The last AlertGroup to be configured
    # @return [Mauve::AlertGroup]
    attr_accessor :last_alert_group

    # Notification methods
    # @return [Hash]
    attr_reader   :notification_methods

    # People
    # @return [Hash]
    attr_reader   :people
    
    # Alert groups
    # @return [Array]
    attr_reader   :alert_groups

    # People lists
    # @return [Hash]
    attr_reader   :people_lists

    # The source lists
    # @return [Hash]
    attr_reader   :source_lists

    #
    # Set up a base config.
    #
    def initialize
      @server = nil
      @last_alert_group = nil
      @notification_methods = {}
      @people = {}
      @people_lists = Hash.new{|h,k| h[k] = Mauve::PeopleList.new(k)}
      @source_lists = Hash.new{|h,k| h[k] = Mauve::SourceList.new(k)}
      @alert_groups = []
    end
    
  end
end

# encoding: UTF-8
require 'mauve/alert'
require 'log4r'

module Mauve
  #
  # This corresponds to a alert_group clause in the configuration.  It is what
  # is used to classify alerts into levels, and thus who gets notified about it
  # and when.
  #
  class AlertGroup < Struct.new(:name, :includes, :acknowledgement_time, :level, :notifications)

    # 
    # Define some constants, and the ordering.
    #
    URGENT = :urgent
    NORMAL = :normal
    LOW    = :low
    LEVELS = [LOW, NORMAL, URGENT]
    
    class << self

      # Finds all AlertGroups that match an alert.
      #
      # @param [Mauve::Alert] alert
      #
      # @return [Array] AlertGroups that match
      def matches(alert)
        grps = find_all { |alert_group| alert_group.includes?(alert) }

        #
        # Make sure we always match the last (and therefore default) group.
        #
        grps << all.last unless grps.include?(all.last)

        grps
      end

      # 
      #
      #
      def find_all(&block)
        return all unless block_given?

        all.find_all do |alert_group|
          yield(alert_group)
        end
      end

      #
      # 
      #
      def find(&block)
        return nil unless block_given?

        all.find do |alert_group|
          yield(alert_group)
        end
      end

      # @return [Log4r::Logger]
      def logger
        Log4r::Logger.new self.to_s
      end

      # All AlertGroups
      #
      # @return [Array]
      def all
        return [] if Configuration.current.nil?

        Configuration.current.alert_groups
      end
      
      # Find all alerts that match 
      #
      # @deprecated Buggy method, use Alert.get_all().
      #
      # This method returns all the alerts in all the alert_groups.  Only
      # the first one should be returned thus making this useless. If you want
      # a list of all the alerts matching a level, use Alert.get_all().
      # 
      # @return [Array]
      def all_alerts_by_level(level)
        Configuration.current.alert_groups.map do |alert_group|
          alert_group.level == level ? alert_group.current_alerts : []
        end.flatten.uniq
      end

    end
    
    # Creates a new AlertGroup
    #
    # @param name Name of alert group
    #
    # @return [AlertGroup] self
    def initialize(name)
      self.name = name
      self.level = :normal
      self.includes = Proc.new { true }
      self
    end
    
    # @return [String]
    def to_s
      "#<AlertGroup:#{name} (level #{level})>"
    end
  
    # The list of current raised alerts in this group.
    #
    # @return [Array] Array of Mauve::Alert
    def current_alerts
      Alert.all(:cleared_at => nil, :raised_at.not => nil).select { |a| includes?(a) }
    end
    
    # Decides whether a given alert belongs in this group according to its
    # includes { } clause
    #
    # @param [Mauve::Alert] alert
    #
    # @return [Boolean] Success or failure.
    def includes?(alert)

      unless alert.is_a?(Alert)
        logger.error "Got given a #{alert.class} instead of an Alert!"
      	logger.debug caller.join("\n")
        return false
      end

      alert.instance_eval(&self.includes) ? true : false
    end

    alias matches_alert? includes?

    # @return [Log4r::Logger]
    def logger ; self.class.logger ; end

    # Signals that a given alert (which is assumed to belong in this group)
    # has undergone a significant change.  We resend this to every notify list.
    # 
    # @param [Mauve::Alert] alert 
    #
    # @return [Boolean] indicates success or failure of alert.
    def notify(alert)
      #
      # If there are no notifications defined. 
      #
      if notifications.nil?
        logger.warn("No notifications found for #{self.inspect}")
        return false
      end

      #
      # This is where we set the reminder -- i.e. on a per-alert-group basis.
      #
      remind_at = notifications.inject(nil) do |reminder_time, notification|
        this_time = notification.remind_at_next(alert)
        if reminder_time.nil? or (!this_time.nil? and  reminder_time > this_time)
          this_time
        else
          reminder_time 
        end
      end

      #
      # OK got the next reminder time.
      #
      unless remind_at.nil?
        this_reminder = AlertChanged.new(
          :level => level.to_s,
          :alert_id => alert.id,
          :person => self.name,
          :at => Time.now,
          :update_type => alert.update_type,
          :remind_at => remind_at,
          :was_relevant => true)

        this_reminder.save
      end

      #
      # The notifications are specified in the config file.
      #
      sent_to = []
      notifications.each do |notification|
        sent_to << notification.notify(alert, sent_to)
      end

      return (sent_to.length > 0)
    end

    # This sorts by priority (urgent first), and then alphabetically, so the
    # first match is the most urgent.
    #
    # @param [Mauve::AlertGroup] other
    #
    # @return [Integer]
    def <=>(other)
      [LEVELS.index(self.level), self.name]  <=> [LEVELS.index(other.level), other.name]
    end

  end

end

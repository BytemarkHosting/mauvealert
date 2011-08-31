# encoding: UTF-8
require 'mauve/alert'
require 'log4r'

module Mauve
  class AlertGroup < Struct.new(:name, :includes, :acknowledgement_time, :level, :notifications)

    # 
    # Define some constants, and the ordering.
    #
    URGENT = :urgent
    NORMAL = :normal
    LOW    = :low
    LEVELS = [LOW, NORMAL, URGENT]
    
    class << self

      def matches(alert)
        grps = all.select { |alert_group| alert_group.includes?(alert) }

        #
        # Make sure we always match the last (and therefore default) group.
        #
        grps << all.last unless grps.include?(all.last)

        grps
      end

      def logger
        Log4r::Logger.new self.to_s
      end

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
      def all_alerts_by_level(level)
        Configuration.current.alert_groups.map do |alert_group|
          alert_group.level == level ? alert_group.current_alerts : []
        end.flatten.uniq
      end

    end
    
    def initialize(name)
      self.name = name
      self.level = :normal
      self.includes = Proc.new { true }
    end
    
    def inspect
      "#<AlertGroup:#{name} (level #{level})>"
    end
  
    # The list of current raised alerts in this group.
    #
    def current_alerts
      Alert.all(:cleared_at => nil, :raised_at.not => nil).select { |a| includes?(a) }
    end
    
    # Decides whether a given alert belongs in this group according to its
    # includes { } clause
    #
    # @param [Alert] alert An alert to test for belongness to group.
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

    def logger ; self.class.logger ; end

    # Signals that a given alert (which is assumed to belong in this group)
    # has undergone a significant change.  We resend this to every notify list.
    #    
    def notify(alert)
      #
      # If there are no notifications defined. 
      #
      if notifications.nil?
        logger.warn("No notifications found for #{self.inspect}")
        return
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

    end

    #
    # This sorts by priority (urgent first), and then alphabetically, so the
    # first match is the most urgent.
    #
    def <=>(other)
      [LEVELS.index(self.level), self.name]  <=> [LEVELS.index(other.level), other.name]
    end

  end

end

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

    # Signals that a given alert (which is assumed to belong in this group) has
    # undergone a significant change.  We resend this to every notify list.
    # The time is used to determine the time to be used when evaluating
    # "during" blocks in the notifier clauses.
    # 
    # @param [Mauve::Alert] alert 
    # @param [Time] at
    #
    # @return [Boolean] indicates success or failure of alert.
    def notify(alert, at=Time.now)
      #
      # If there are no notifications defined. 
      #
      if notifications.nil?
        logger.warn("No notifications found for #{self.inspect}")
        return false
      end

      during_runners = [] 

      #
      # This is where we set the reminder -- i.e. on a per-alert-group basis.
      
      remind_at = nil
      notifications.each do |notification|
        #
        # Create a new during_runner for this notification clause, and keep it
        # handy.
        #
        during_runner = DuringRunner.new(at, alert, &notification.during)
        during_runners << during_runner

        #
        # Work out the next reminder time
        #
        this_remind_at = notification.remind_at_next(alert, during_runner)

        #
        # Skip this one if no reminder time can be found
        #
        next if this_remind_at.nil?

        #
        # Set the next reminder time if we've not had one already.
        #
        remind_at = this_remind_at if remind_at.nil?

        #
        # We need the next soonest reminder time.
        #
        remind_at = this_remind_at if remind_at > this_remind_at
      end

      #
      # OK got the next reminder time.
      #
      unless remind_at.nil?
        this_reminder = AlertChanged.new(
          :level => level.to_s,
          :alert_id => alert.id,
          :person => self.name,
          :at => at,
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
        sent_to << notification.notify(alert, sent_to, during_runners.shift)
      end

      #
      # If the alert is ack'd or cleared, notify anyone who has contributed to
      # its history since it was raised.
      #
      alert.extra_people_to_notify.each do |person|
        person.notifications.each do |n|
          notification = Mauve::Notification.new(person)
          notification.level  = self.level
          notification.every  = n.every
          notification.during = n.during
          notification
          sent_to << notification.notify(alert, sent_to, DuringRunner.new(at, alert, &notification.during))
        end
      end if alert.acknowledged? or alert.cleared?

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

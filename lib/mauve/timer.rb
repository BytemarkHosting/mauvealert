# encoding: UTF-8
require 'mauve/alert'
require 'mauve/notifier'
require 'mauve/mauve_thread'
require 'thread'
require 'log4r'

module Mauve

  class Timer < MauveThread

    include Singleton

    attr_accessor :sleep_interval, :last_run_at

    def initialize
      @logger = Log4r::Logger.new self.class.to_s
      @logger.info("Timer singleton created.")
      @initial_sleep = 300
      @initial_sleep_threshold = 300
    end

    def main_loop
      #
      # Get the next alert.
      #
      next_alert = Alert.find_next_with_event

      #
      # If we didn't find an alert, or the alert we found is due in the future,
      # look for the next alert_changed object.
      #
      if next_alert.nil? or next_alert.due_at > MauveTime.now
        @logger.debug("Next alert was #{next_alert} due at #{next_alert.due_at}") unless next_alert.nil?
        next_alert_changed = AlertChanged.find_next_with_event
      end

      if next_alert_changed.nil? and next_alert.nil?
        next_to_notify = nil

      elsif next_alert.nil? or next_alert_changed.nil?
        next_to_notify = (next_alert || next_alert_changed)

      else
        next_to_notify = ( next_alert.due_at < next_alert_changed.due_at ? next_alert : next_alert_changed )

      end

      #
      # Nothing to notify?
      #
      if next_to_notify.nil? 
        #
        # Sleep indefinitely
        #
        @logger.debug("Nothing to notify about -- snoozing indefinitely.")
      else
        #
        # La la la nothing to do.
        #
        @logger.debug("Next to notify: #{next_to_notify} -- snoozing until #{next_to_notify.due_at}")
      end

      #
      # Ah-ha! Sleep with a break clause.
      #
      while next_to_notify.nil? or MauveTime.now <= next_to_notify.due_at
        #
        # Start again if the situation has changed.
        #
        break if self.should_stop?
        #
        # This is a rate-limiting step for alerts.
        #
        Kernel.sleep 0.1
        #
        # Not sure if this is needed or not.  But the timer thread seems to
        # freeze here, apparently stuck on a select() statement.
        #
        Thread.pass
      end

      return if self.should_stop? or next_to_notify.nil?

      next_to_notify.poll
    end

  end

end

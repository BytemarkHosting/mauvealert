# encoding: UTF-8
require 'mauve/alert'
require 'mauve/notifier'
require 'mauve/mauve_thread'
require 'thread'
require 'log4r'

module Mauve

  class Timer < MauveThread

    include Singleton

    def main_loop
      #
      # Get the next alert.
      #
      next_alert = Alert.find_next_with_event

      #
      # If we didn't find an alert, or the alert we found is due in the future,
      # look for the next alert_changed object.
      #
      if next_alert.nil? or next_alert.due_at > Time.now
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
        logger.info("Nothing to notify about -- snoozing for a while.")
        sleep_loops = 600
      else
        #
        # La la la nothing to do.
        #
        logger.info("Next to notify: #{next_to_notify} #{next_to_notify.is_a?(AlertChanged) ? "(reminder)" : "(heartbeat)"} -- snoozing until #{next_to_notify.due_at.iso8601}")
        sleep_loops = ((next_to_notify.due_at - Time.now).to_f / 0.1).round.to_i
      end

      sleep_loops = 1 if sleep_loops.nil? or sleep_loops < 1

      #
      # Ah-ha! Sleep with a break clause.
      #
      sleep_loops.times do
        #
        # Start again if the situation has changed.
        #
        break if self.should_stop?

        #
        # This is a rate-limiting step for alerts.
        #
        Kernel.sleep 0.1
      end

      return if self.should_stop? or next_to_notify.nil?

      next_to_notify.poll
    end

  end

end

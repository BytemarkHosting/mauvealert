require 'mauve/mauve_thread'
require 'mauve/notifiers'

module Mauve

  # The Notifier is reponsible for popping notifications off the
  # notification_buffer run by the Mauve::Server instance.  This ensures that
  # notifications are sent in a separate thread to the main processing /
  # updating threads, and stops notifications delaying updates.
  #
  #
  class Notifier < MauveThread
    
    include Singleton

    # Stop the notifier thread.  This just makes sure that all the
    # notifications in the buffer have been sent.
    #
    def stop
      super

      #
      # Flush the queue.
      #
      main_loop
    end
    
    #
    # This sends the notification for an alert
    #
    def notify(alert, at)
      #
      # Make sure we're looking at a fresh copy of the alert.
      #
      alert.reload

      #
      # Forces alert-group to be re-evaluated on notification.
      #
      alert.cached_alert_group = nil
      this_alert_group = alert.alert_group

      #
      # This saves without callbacks if the cached_alert_group has been
      # altered.
      #
      alert.save! if alert.dirty?

      if this_alert_group.nil?
        logger.warn "Could not notify for #{alert} since there are no matching alert groups"

      else
        this_alert_group.notify(alert, at)

      end
    end


    private

    # This is the main loop that is executed in the thread.
    #
    #
    def main_loop
      # 
      # Cycle through the buffer.
      #
      sz = Server.notification_buffer_size

      logger.info "Sending #{sz} alerts" if sz > 0

      #
      # Empty the buffer, one notification at a time.
      #
      sz.times do
        notify(*Server.notification_pop)
      end
    end

  end

end



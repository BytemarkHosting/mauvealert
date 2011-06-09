# encoding: UTF-8
require 'timeout'
require 'log4r'

module Mauve
  class Person < Struct.new(:username, :password, :holiday_url, :urgent, :normal, :low, :email, :xmpp, :sms)
  
    attr_reader :notification_thresholds
  
    def initialize(*args) 
      @notification_thresholds = { 60 => Array.new(10) }
      @suppressed = false
      super(*args)
    end
   
    def logger ; @logger ||= Log4r::Logger.new self.class.to_s ; end
 
    def suppressed?
      @suppressed
    end
    
    # This class implements an instance_eval context to execute the blocks
    # for running a notification block for each person.
    # 
    class NotificationCaller

      def initialize(person, alert, other_alerts, notification_methods, base_conditions={})
        @person = person
        @alert = alert
        @other_alerts = other_alerts
        @notification_methods = notification_methods
        @base_conditions = base_conditions
      end
      
      def logger ; @logger ||= Log4r::Logger.new self.class.to_s ; end

      #
      # This method makes sure things liek
      #
      #   xmpp 
      #   works
      #
      def method_missing(name, *args)
        #
        # Work out the destination
        #
        if args.first.is_a?(String)
          destination = args.pop
        else 
          destination = @person.__send__(name)
        end

        if args.first.is_a?(Array)
          conditions  = @base_conditions.merge(args[0])
        end

        notification_method = Configuration.current.notification_methods[name.to_s]

        raise NoMethodError.new("#{name} not defined as a notification method") unless notification_method

        # Methods are expected to return true or false so the user can chain
        # them together with || as fallbacks.  So we have to catch exceptions
        # and turn them into false.
        #
        res = notification_method.send_alert(destination, @alert, @other_alerts, conditions)
        #
        # Log the result
        logger.debug "Notification " +  (res ? "succeeded" : "failed" ) + " for #{@person.username} using notifier '#{name}' to '#{destination}'"

        res
      end

    end 
    
    ## Deals with changes in an alert.
    # 
    # == Old comments by Matthew.
    #
    # An AlertGroup tells a Person that an alert has changed.  Within
    # this alert group, the alert may or may not be "relevant" to this
    # person, but it is ultimately up to the Person to decide whether to
    # send a notification.  (i.e. notification of acks/clears should
    # always go out to a Person who was notified of the original alert,
    # even if the alert is no longer relevant to them).
    # 
    # == New comment
    #
    # The old code works like this:  An alert arrives, with a relevance.  An
    # AlertChanged is created and the alert may or may not be send.  The 
    # problem is that alerts can be relevant AFTER the initial raise and this
    # code (due to AlertChange.was_relevant_when_raised?()) will ignore it.
    # This is wrong.
    # 
    #
    # The Thread.exclusive wrapper around the AlertChanged creation makes 
    # sure that two AlertChanged are not created at the same time.  This 
    # caused both instances to set the remind_at time of the other to nil. 
    # Thus reminders were never seen which is clearly wrong.  This bug was
    # only showing on jruby due to green threads in MRI. 
    #
    # 
    # @author Matthew Bloch, Yann Golanski
    # @param [symb] level Level of the alert.
    # @param [Alert] alert An alert object.
    # @param [Boolean] Whether the alert is relevant as defined by notification
    #                  class.
    # @param [MauveTime] When to send remind.
    # @return [NULL] nada
    def alert_changed(level, alert, is_relevant=true, remind_at=nil)
        # User should get notified but will not since on holiday.
        str = String.new
#        if is_on_holiday?
#          is_relevant = false
#          str = ' (user on holiday)'
#        end

        # Deals with AlertChange database entry.
        last_change = AlertChanged.first(:alert_id => alert.id, :person => username)
        if not last_change.nil?
          if not last_change.remind_at.nil? and not remind_at.nil?
            if last_change.remind_at.to_time < remind_at
              remind_at = last_change.remind_at.to_time
            end
          end
        end

        new_change = AlertChanged.create(
            :level => level.to_s,
            :alert_id => alert.id, 
            :at => MauveTime.now, 
            :person => username, 
            :update_type => alert.update_type,
            :remind_at => remind_at,
            :was_relevant => is_relevant)

        # We need to look at the AlertChanged objects to reset them to
        # the right value.  What is the right value?   Well...
        if true == is_relevant
          last_change.was_relevant = true if false == last_change.nil?
        end

        # Send the notification is need be.
        if !last_change || last_change.update_type.to_sym == :cleared
          # Person has never heard of this alert before, or previously cleared.
          #
          # We don't send any alert if such a change isn't relevant to this
          # Person at this time.
          send_alert(level, alert) if is_relevant and [:raised, :changed].include?(alert.update_type.to_sym)

        else
          # Relevance is determined by whether the user heard of this alert
          # being raised.
          send_alert(level, alert) if last_change.was_relevant_when_raised? 
        end
    end
    
    def remind(alert, level)
      logger.debug("Reminder for #{alert} send at level #{level}.")
      send_alert(level, alert)
    end
   
    #
    # This just wraps send_alert by sending the job to a queue.
    #
    def send_alert(level, alert)
      Notifier.push([self, level, alert])
    end

    def do_send_alert(level, alert)
      now = MauveTime.now
      suppressed_changed = nil
      threshold_breached = @notification_thresholds.any? do |period, previous_alert_times|
          first = previous_alert_times.first
          first.is_a?(MauveTime) and (now - first) < period
        end

      this_alert_suppressed = false

      if Server.instance.started_at > alert.updated_at.to_time and (Server.instance.started_at + Server.instance.initial_sleep) > MauveTime.now
        logger.warn("Alert last updated in prior run of mauve -- ignoring for initial sleep period.")
        this_alert_suppressed = true
      elsif threshold_breached
        unless suppressed?
          logger.warn("Suspending notifications to #{username} until further notice.") 
          suppressed_changed = true 
        end
        @suppressed = true
      else
        if suppressed?
          suppressed_changed = false
          logger.warn "Starting to send notifications again for #{username}."
        else
          logger.info "Notifying #{username} of #{alert} at level #{level}"
        end
        @suppressed = false
      end
      
      return if suppressed? or this_alert_suppressed

      result = NotificationCaller.new(
        self,
        alert,
        current_alerts,
        Configuration.current.notification_methods,
        :suppressed_changed => suppressed_changed
      ).instance_eval(&__send__(level))

      if result
        # 
        # Remember that we've sent an alert
        #
        @notification_thresholds.each do |period, previous_alert_times|
          @notification_thresholds[period].replace(previous_alert_times[1..period-1] + [now])
        end

        logger.info("Notification for #{username} of #{alert} at level #{level} has been successful")
      else
        logger.error("Failed to notify #{username} about #{alert} at level #{level}")
      end
    end
    
    # Returns the subset of current alerts that are relevant to this Person.
    #
    def current_alerts
      Alert.all_raised.select do |alert|
        my_last_update = AlertChanged.first(:person => username, :alert_id => alert.id)
        my_last_update && my_last_update.update_type != :cleared
      end
    end
    
    protected
    # Remembers that an alert has been sent so that we can later check whether
    # too many alerts have been sent in a particular period.
    #
    def remember_alert(now=MauveTime.now)
    end
    
    # Returns time period over which "too many" alerts have been sent, or nil
    # if none.
    #
    def threshold_breached(now=MauveTime.now)
    end

    # Whether the person is on holiday or not.
    #
    # @return [Boolean] True if person on holiday, false otherwise.
    def is_on_holiday? ()
      return false if true == holiday_url.nil? or '' == holiday_url
      return CalendarInterface.is_user_on_holiday?(holiday_url, username)
    end

  end

end

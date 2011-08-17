# encoding: UTF-8
require 'timeout'
require 'log4r'

module Mauve
  class Person < Struct.new(:username, :password, :holiday_url, :urgent, :normal, :low, :email, :xmpp, :sms)
  
    attr_reader :notification_thresholds
  
    def initialize(*args)
      #
      # By default send 10 thresholds in a minute maximum
      #
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

      def initialize(person, alert, other_alerts, base_conditions={})
        @person = person
        @alert = alert
        @other_alerts = other_alerts
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
        else
          conditions  = @base_conditions
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
        note =  "#{@alert.update_type.capitalize} #{name} notification to #{@person.username} (#{destination}) " +  (res ? "succeeded" : "failed" )
        logger.info note+" about #{@alert}."
        h = History.new(:alerts => [@alert], :type => "notification", :event => note)
        logger.error "Unable to save history due to #{h.errors.inspect}" if !h.save

        return res
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

        send_alert(level, alert) if is_relevant # last_change.was_relevant_when_raised? 
    end
   
    #
    # This just wraps send_alert by sending the job to a queue.
    #
    def send_alert(level, alert)
      Server.notification_push([self, level, alert])
    end
   
    def do_send_alert(level, alert)
      now = Time.now

      was_suppressed = self.suppressed?

      @suppressed = @notification_thresholds.any? do |period, previous_alert_times|
          #
          # Choose the second one as the first.
          #
          first = previous_alert_times[1]
          first.is_a?(Time) and (now - first) < period
      end

      if self.suppressed?
        logger.info("Suspending further notifications to #{username} until further notice.") unless was_suppressed
        
      else
        logger.info "Starting to send notifications again for #{username}." if was_suppressed

      end
      
      if Server.instance.started_at > alert.updated_at and (Server.instance.started_at + Server.instance.initial_sleep) > Time.now
        logger.info("Alert last updated in prior run of mauve -- ignoring for initial sleep period.")
        return true
      end
      
      #
      # We only suppress notifications if we were suppressed before we started,
      # and are still suppressed.
      #
      if was_suppressed and self.suppressed?
        note =  "#{alert.update_type.capitalize} notification to #{self.username} suppressed"
        logger.info note + " about #{alert}."
        History.create(:alerts => [alert], :type => "notification", :event => note)
        return true 
      end

      result = NotificationCaller.new(
        self,
        alert,
        current_alerts,
        {:is_suppressed  => @suppressed,
         :was_suppressed => was_suppressed, }
      ).instance_eval(&__send__(level))

      if result
        # 
        # Remember that we've sent an alert
        #
        @notification_thresholds.each do |period, previous_alert_times|
          #
          # Hmm.. not sure how to make this thread-safe.
          #
          @notification_thresholds[period].push Time.now
          @notification_thresholds[period].shift
        end
        true

      else
        false

      end
    end
    
    # Returns the subset of current alerts that are relevant to this Person.
    #
    def current_alerts
      Alert.all_raised.select do |alert|
        my_last_update = AlertChanged.first(:person => username, :alert_id => alert.id)
        my_last_update && my_last_update.update_type != "cleared"
      end
    end
    
    protected
    # Whether the person is on holiday or not.
    #
    # @return [Boolean] True if person on holiday, false otherwise.
    def is_on_holiday? ()
      return false if true == holiday_url.nil? or '' == holiday_url
      return CalendarInterface.is_user_on_holiday?(holiday_url, username)
    end

  end

end

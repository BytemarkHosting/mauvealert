# encoding: UTF-8
require 'timeout'
require 'log4r'

module Mauve
  class Person < Struct.new(:username, :password, :holiday_url, :urgent, :normal, :low, :email, :xmpp, :sms)
  
    attr_reader :notification_thresholds, :last_pop3_login
  
    def initialize(*args)
      #
      # By default send 10 thresholds in a minute maximum
      #
      @notification_thresholds = { 60 => Array.new(10) }
      @suppressed = false
      #
      # TODO fix up web login so pop3 can be used as a proxy.
      #
      @last_pop3_login = {:from => nil, :at => nil}
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
      # This method makes sure things like
      #
      #   xmpp
      #
      #  works
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

    #
    # Sends the alert, and updates when the AlertChanged database to set the next reminder.
    #
    def send_alert(level, alert, is_relevant=true, remind_at=nil)
      #
      # First check that we've not just sent an notification to this person for
      # this alert
      #
      last_reminder = AlertChanged.first(:alert => alert, :person => username, :update_type => alert.update_type, :at.gte => (Time.now - 1.minute) )

      if last_reminder and last_reminder.at >= (Time.now - 1.minute)
        #
        #
        logger.info("Not sending notification to #{username} for #{alert} because one has just been sent.")
        return false
      end


      this_reminder = AlertChanged.new(
        :level => level.to_s,
        :alert_id => alert.id, 
        :person => username, 
        :at => Time.now,
        :update_type => alert.update_type,
        :remind_at => remind_at,
        :was_relevant => is_relevant)

      #
      # Check to make sure that we've not got a sooner reminder set.
      #
      unless remind_at.nil?
        next_reminder = AlertChanged.first(:alert => alert, :remind_at.gt => Time.now, :person => username, :update_type => alert.update_type)

        if next_reminder
          #
          # If the reminder is further in the future than the one we're about
          # to put on, then just update it.
          #
          # Otherwise if it is sooner, we don't need to create a new one.
          #
          if next_reminder.remind_at > remind_at
            next_reminder.remind_at = remind_at
            logger.info("Not inserting a new reminder, as there is already one in place sooner")
            this_reminder = next_reminder
          else
            this_reminder = nil
          end
        end
      end

      this_reminder.save unless this_reminder.nil?

      if is_relevant
        Server.notification_push([self, level, alert])
        return true
      end

      return false
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

        return true
      end

      return false
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

# encoding: UTF-8
require 'timeout'
require 'log4r'

module Mauve
  class Person < Struct.new(:username, :password, :holiday_url, :urgent, :normal, :low, :email, :xmpp, :sms)
  
    attr_reader :notification_thresholds, :last_pop3_login, :suppressed
 
    # Set up a new Person
    #
    # @param [Hash] args The options for setting up the person
    #   @option args [String] :username The person's username
    #   @option args [String] :password The SHA1 sum of the person's password
    #   @option args [String] :holiday_url The URL that can be checked by Mauve::CalendarInterface#is_user_on_holiday?
    #   @option args [Proc] :urgent The block to execute when an urgent-level notification is issued
    #   @option args [Proc] :normal The block to execute when an normal-level notification is issued
    #   @option args [Proc] :low The block to execute when an low-level notification is issued
    #   @option args [String] :email The person's email address
    #   @option args [String] :sms The person's mobile number
    # 
    def initialize(*args)
      @notification_thresholds = nil
      @suppressed = false
      #
      # TODO fix up web login so pop3 can be used as a proxy.
      #
      @last_pop3_login = {:from => nil, :at => nil}
      super(*args)
    end
   
    # @return Log4r::Logger
    def logger ; @logger ||= Log4r::Logger.new self.class.to_s ; end

    # Determines if notifications to the user are currently suppressed
    #
    # @return [Boolean]
    def suppressed? ; @suppressed ; end
 
    # Works out if a notification should be suppressed.  If no parameters are supplied, it will 
    #
    # @param [Time] Theoretical time of notification
    # @param [Time] Current time.
    # @return [Boolean] If suppression is needed.
    def should_suppress?(with_notification_at = nil, now = Time.now)

      return self.notification_thresholds.any? do |period, previous_alert_times|
        #
        # This is going to work out if we would be suppressed if 
        if with_notification_at.nil?
         first = previous_alert_times.first
         last  = previous_alert_times.last
        else
         first = previous_alert_times[1]
         last  = with_notification_at
        end
   
        (first.is_a?(Time) and (now - first) < period) or
          (last.is_a?(Time) and @suppressed and (now - last) < period) 
      end
    end
   
    # The notification thresholds for this user
    #
    # @return [Hash]
    def notification_thresholds
      @notification_thresholds ||= { } 
    end
 
    # This class implements an instance_eval context to execute the blocks
    # for running a notification block for each person.
    # 
    class NotificationCaller

      # Set up the notification caller
      #
      # @param [Mauve::Person] person
      # @param [Mauve::Alert] alert
      # @param [Array] other_alerts
      # @param [Hash] base_conditions
      #
      def initialize(person, alert, other_alerts, base_conditions={})
        @person = person
        @alert = alert
        @other_alerts = other_alerts
        @base_conditions = base_conditions
      end
      
      # @return Log4r::Logger
      def logger ; @logger ||= Log4r::Logger.new self.class.to_s ; end

      # This method makes sure things like +xmpp+ and +email+ work.
      #
      # @param [String] name The notification method to use
      # @param [Array or Hash] args Extra conditions to pass to this notification method
      #
      # @return [Boolean] if the notifcation has been successful
      def method_missing(name, *args)
        #
        # Work out the notification method
        #
        notification_method = Configuration.current.notification_methods[name.to_s]

        @logger.warn "Notification method '#{name}' not defined  (#{@person.username})" if notification_method.nil?

        #
        # Work out the destination
        #
        if args.first.is_a?(String)
          destination = args.pop
        elsif @person.respond_to?(name)
          destination = @person.__send__(name)
        else
          destination = nil
        end

        @logger.warn "#{name} destination for #{@person.username} not set" if destination.nil?

        if args.first.is_a?(Array)
          conditions  = @base_conditions.merge(args[0])
        else
          conditions  = @base_conditions
        end


        if notification_method and destination 
          # Methods are expected to return true or false so the user can chain
          # them together with || as fallbacks.  So we have to catch exceptions
          # and turn them into false.
          #
          res = notification_method.send_alert(destination, @alert, @other_alerts, conditions)
        else
          res = false
        end

        #
        # Log the result
        note =  "#{@alert.update_type.capitalize} #{name} notification to #{@person.username} (#{destination}) " +  (res ? "succeeded" : "failed" )
        logger.info note+" about #{@alert}."
        h = History.new(:alerts => [@alert], :type => "notification", :event => note)
        logger.error "Unable to save history due to #{h.errors.inspect}" if !h.save

        return res
      end

    end 

    # Sends the alert
    #
    # @param [Symbol] level Level at which the alert should be sent
    # @param [Mauve::Alert] alert Alert we're notifiying about
    #
    # @return [Boolean] if the notification was successful
    def send_alert(level, alert)
      now = Time.now

      was_suppressed = @suppressed
      @suppressed    = self.should_suppress?
      will_suppress  = self.should_suppress?(now)

      logger.info "Starting to send notifications again for #{username}." if was_suppressed and not @suppressed
      
      #
      # We only suppress notifications if we were suppressed before we started,
      # and are still suppressed.
      #
      if @suppressed or self.is_on_holiday?
        note =  "#{alert.update_type.capitalize} notification to #{self.username} suppressed"
        logger.info note + " about #{alert}."
        History.create(:alerts => [alert], :type => "notification", :event => note)
        return true 
      end

      result = NotificationCaller.new(
        self,
        alert,
        [],
        # current_alerts,
        {:will_suppress  => will_suppress,
         :was_suppressed => was_suppressed, }
      ).instance_eval(&__send__(level))

      if [result].flatten.any?
        # 
        # Remember that we've sent an alert
        #
        self.notification_thresholds.each do |period, previous_alert_times|
          #
          # Hmm.. not sure how to make this thread-safe.
          #
          self.notification_thresholds[period].push now
          self.notification_thresholds[period].shift
        end


        return true
      end

      return false
    end
   
    # 
    # Returns the subset of current alerts that are relevant to this Person.
    #
    # This is currently very CPU intensive, and slows things down a lot.  So
    # I've commented it out when sending notifications.
    #
    # @return [Array] alerts relevant to this person
    def current_alerts
      Alert.all_raised.select do |alert|
        my_last_update = AlertChanged.first(:person => username, :alert_id => alert.id)
        my_last_update && my_last_update.update_type != "cleared"
      end
    end
    
    # Whether the person is on holiday or not.
    #
    # @return [Boolean] True if person on holiday, false otherwise.
    def is_on_holiday? ()
      return false if holiday_url.nil? or holiday_url.empty?

      return CalendarInterface.is_user_on_holiday?(holiday_url)
    end

  end

end

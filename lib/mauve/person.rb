# encoding: UTF-8
require 'timeout'
require 'log4r'

module Mauve
  class Person 
  
    attr_reader :username, :password, :urgent, :normal, :low, :email, :xmpp, :sms
    attr_reader :notification_thresholds, :last_pop3_login, :suppressed, :notifications
    attr_reader :notify_when_off_sick, :notify_when_on_holiday

    # Set up a new Person
    #
    def initialize(username)
      @notification_thresholds = nil
      @suppressed = false
      #
      # TODO fix up web login so pop3 can be used as a proxy.
      #
      @last_pop3_login = {:from => nil, :at => nil}
      @notifications = []

      @username = username
      @password = nil
      @urgent   = @normal = @low  = nil
      @email    = @sms    = @xmpp = nil
   
      @notify_when_on_holiday = @notify_when_off_sick = false 
    end
  
    # Determines if a user should be notified if they're ill.
    #
    # @return [Boolean]
    #
    def notify_when_off_sick!
      @notify_when_off_sick = true
    end

    # Determines if a user should be notified if they're on their holdiays.
    #
    # @return [Boolean]
    #
    def notify_when_on_holiday!
      @notify_when_on_holiday = true
    end

    # Sets the Proc to call for urgent notifications
    #
    def urgent=(block)
      raise ArgumentError, "urgent expects a block, not a #{block.class}" unless block.is_a?(Proc)
      @urgent = block
    end
 
    # Sets the Proc to call for normal notifications
    #
    def normal=(block)
      raise ArgumentError, "normal expects a block, not a #{block.class}" unless block.is_a?(Proc)
      @normal = block
    end
    
    # Sets the Proc to call for low notifications
    #
    def low=(block)
      raise ArgumentError, "low expects a block, not a #{block.class}" unless block.is_a?(Proc)
      @low = block
    end

    # Sets the email parameter
    #
    #
    def email=(arg)
      raise ArgumentError, "email expects a string, not a #{arg.class}" unless arg.is_a?(String)
      @email = arg
    end

    # Sets the sms parameter
    #
    #
    def sms=(arg)
      raise ArgumentError, "sms expects a string, not a #{arg.class}" unless arg.is_a?(String)
      @sms = arg
    end

    # Sets the xmpp parameter
    #
    #
    def xmpp=(arg)
      # raise ArgumentError, "xmpp expected a string, not a #{arg.class}" unless arg.is_a?(String) or arg.is_a?(Jabber::JID)
      @xmpp = arg
    end

    # Sets the password parameter
    #
    #
    def password=(arg)
      raise ArgumentError, "password expected a string, not a #{arg.class}" unless arg.is_a?(String)
      @password=arg
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

        logger.warn "Notification method '#{name}' not defined  (#{@person.username})" if notification_method.nil?

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

        logger.warn "#{name} destination for #{@person.username} not set" if destination.nil?

        if args.first.is_a?(Hash)
          conditions  = @base_conditions.merge(args.pop)
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
        h = History.new(:alerts => [@alert], :type => "notification", :event => note, :user => @person.username)
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
    def send_alert(level, alert, now=Time.now)

      was_suppressed = @suppressed
      @suppressed    = self.should_suppress?
      will_suppress  = self.should_suppress?(now)

      logger.info "Starting to send notifications again for #{username}." if was_suppressed and not @suppressed
      
      #
      # We only suppress notifications if we were suppressed before we started,
      # and are still suppressed.
      #
      if @suppressed or self.is_on_holiday?(now) or self.is_off_sick?(now)
        note =  "#{alert.update_type.capitalize} notification to #{self.username} suppressed"
        logger.info note + " about #{alert}."
        History.create(:alerts => [alert], :type => "notification", :event => note, :user => self.username)
        return true 
      end

      result = false

      #
      # Make sure the level we want has been defined as a Proc.
      #
      if __send__(level).is_a?(Proc)
        result = NotificationCaller.new(
          self,
          alert,
          [],
          # current_alerts,
          {:will_suppress  => will_suppress,
           :was_suppressed => was_suppressed, }
        ).instance_eval(&__send__(level))
      end

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
    def is_on_holiday?(at=Time.now)
      return false if self.notify_when_on_holiday

      return CalendarInterface.is_user_on_holiday?(self.username, at)
    end

    def is_off_sick?(at=Time.now)
      return false if self.notify_when_off_sick

      return CalendarInterface.is_user_off_sick?(self.username, at)
    end

    def resolve_notifications(default_every=nil, default_during=nil, at = nil)
      self.notifications.collect do |notification|
        this_notification = Notification.new(self)
        this_notification.every  = default_every  || notification.every
        this_notification.during = default_during || notification.during
        this_notification
      end.flatten.compact
    end

  end

end

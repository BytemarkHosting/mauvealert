# encoding: UTF-8
require 'mauve/person'
require 'mauve/notifiers'

module Mauve
  # This class provides an execution context for the code found in 'during'
  # blocks in the configuration file.  This code specifies when an alert
  # should cause notifications to be generated, and can access @time and
  # \@alert variables.  There are also some helper methods to provide
  # oft-needed functionality such as hours_in_day.
  #
  # e.g. to send alerts only between 10 and 11 am:
  #
  #   during = Proc.new { @time.hour == 10 }
  #   
  # ... later on ...
  #   
  #   DuringRunner.new(Time.now, my_alert, &during).now?
  #
  # ... or to ask when an alert will next be cued ...
  #
  #   DuringRunner.new(Time.now, my_alert, &during).find_next
  #
  # which will return a Time object, or nil if the time period will
  # not be valid again, at least not in the next week.
  #
  class DuringRunner

    attr_reader :time, :alert, :during

    #
    # Sets up the class
    #
    # @param [Time] time The time we're going to test
    # @param [Mauve::Alert or Nilclass] alert The alert that we can use in tests.
    # @param [Proc] during The Proc that is evaluated inside the instance to decide if now is now!
    # @raise [ArgumentError] if +time+ is not a Time
    #
    def initialize(time, alert=nil, &during)
      raise ArgumentError.new("Must supply time (not #{time.inspect})") unless time.is_a?(Time)
      @time = time
      @alert = alert
      @during = during || Proc.new { true }
      @logger = Log4r::Logger.new "Mauve::DuringRunner"
      @now_cache = Hash.new
    end
    
    # This evaluates the +during+ block, returning the result.
    #
    # @param [Time] t Set the time at which to evaluate the +during+ block.
    # @return [Boolean]
    def now?(t=@time)
      #
      # Use the cache if we've already worked out what happens at time t.
      #
      return @now_cache[t] if @now_cache.has_key?(t)
     
      #
      # Store the test time in an instance variable so the test knows what time
      # we're testing against.
      #
      @test_time = t

      #
      # Store the answer in our cache and return.
      #
      @now_cache[t] = (instance_eval(&@during) ? true : false)
    end

    # This finds the next occurance of the +during+ block evaluating to true.
    # It returns nil if an occurence cannot be found within the next 8 days.
    #
    # @param [Integer] after Skip time forward this many seconds before starting
    # @return [Time or nil]
    #
    def find_next(after = 0)
      t = @time+after
      #
      # If the condition is true after x seconds, return the time in x seconds.
      #
      return t if self.now?(t)

      #
      # Otherwise calculate when the condition is next true.
      #
      step = 3600
      while t <= @time + 8.days
        #
        # If we're currently OK, and we won't be OK after the next step (or
        # vice-versa) decrease step size, and try again
        #
        if false == self.now?(t) and true == self.now?(t+step)
          #
          # Unless we're on the smallest step, try a smaller one.
          #
          if step == 1
            t += step
            break 
          end

          step /= 60
          next
        end

        #
        # Decrease the time by the step size if we're currently OK.
        #
        t += step
      end 
      
      return t if self.now?(t)
      
      nil # never again
    end
    
    protected

    # Test to see if a people_list is empty.  NB this is just evaluated at the
    # time that the DuringRunner is set up with.
    #
    # @param [String] people_list People list to query
    # @return [Boolean]
    #
    def no_one_in(people_list)
      return true unless Configuration.current.people[people_list].respond_to?(:people)
      
      #
      # Cache the results to prevent hitting the calendar too many times.
      #
      @no_one_in_cache ||= Hash.new

      return @no_one_in_cache[people_list] if @no_one_in_cache.has_key?(people_list)

      @no_one_in_cache[people_list] = Configuration.current.people[people_list].people(@time).empty?
    end

    # Returns true if the current hour is in the list of hours given.
    # 
    # @param [Array] hours List of hours (as Integers)
    # @return [Boolean]
    def hours_in_day(*hours)
      @test_time = @time if @test_time.nil?
      x_in_list_of_y(@test_time.hour, Configuration.parse_range(hours).flatten)
    end   
 
    # Returns true if the current day is in the list of days given
    #
    # @param [Array] days List of days (as Integers)
    # @return [Boolean]
    def days_in_week(*days)
      @test_time = @time if @test_time.nil?
      x_in_list_of_y(@test_time.wday, Configuration.parse_range(days,0...7).flatten)
    end
    
    # Tests if the alert has not been acknowledged within a certain time.
    #
    # @param [Integer] seconds Number of seconds
    # @return [Boolean]
    def unacknowledged(seconds)
      @test_time = @time if @test_time.nil?
      @alert &&
        @alert.raised? &&
        !@alert.acknowledged? &&
        (@test_time - @alert.raised_at) >= seconds
    end
    
    # Tests if the alert has raised for a certain time.
    #
    # @param [Integer] seconds Number of seconds
    # @return [Boolean]
    def raised_for(seconds)
      @test_time = @time if @test_time.nil?
      @alert &&
        @alert.raised? &&
        (@test_time - @alert.raised_at) >= seconds
    end


    # Checks to see if x is contained in y
    #
    # @param [Array] y Array to search for +x+
    # @param [Object] x
    # @return [Boolean]
    def x_in_list_of_y(x,y)
      y.any? do |range|
        if range.respond_to?("include?")
          range.include?(x)
        else
          range == x
        end
      end
    end

    # Test to see if we're in working hours.  See Time#working_hours?
    #
    # @return [Boolean]
    def working_hours?
      @test_time = @time if @test_time.nil?
      @test_time.working_hours?
    end

    #
    # Return true if today is a bank holiday
    #
    def bank_holiday?
      @test_time = @time if @test_time.nil?
      @test_time.bank_holiday?
    end

    # Test to see if we're in the dead zone.  See Time#dead_zone?
    #
    # @return [Boolean]
    def dead_zone?
      @test_time = @time if @test_time.nil?
      @test_time.dead_zone?
    end

    # 
    # Return true if we're in daytime_hours.  See Time#daytime_hours?
    #
    def daytime_hours?
      @test_time = @time if @test_time.nil?
      @test_time.daytime_hours?
    end
  end
  
  # A Notification is an instruction to notify a person, or a list of people,
  # at a particular alert level, on a periodic basis, and optionally under
  # certain conditions specified by a block of code.
  #
  class Notification

    attr_reader :during, :every, :level, :usernames

    # Set up a new notification
    #
    # @param [Array] usernames List of Mauve::Person to notify
    # @param [Symbol] level Level at which to notify
    def initialize(*usernames)
      @usernames = usernames.flatten.collect do |u|
        if u.respond_to?(:username)
          u.username
        else
          u.to_s
        end
      end.flatten

      @during = nil
      @every = nil
      @level = nil
    end

    # @return [String]
    def to_s
      "#<Notification:of #{usernames} at level #{level} every #{every}>"
    end

    # @return Log4r::Logger 
    def logger ;  Log4r::Logger.new self.class.to_s ; end

    def during=(arg)
      @during = arg
    end

    def every=(arg)
      @every = arg
    end

    def level=(arg)
      @level = arg
    end

    def usernames=(arg)
      @usernames = arg
    end

    def people
      usernames.sort.collect do |username|
        Configuration.current.people[username]
      end.compact.uniq
    end

    # Push a notification on to the queue for this alert.  The Mauve::Notifier
    # will then pop it off and do the notification in a separate thread.
    #
    # @param [Mauve::Alert or Mauve::AlertChanged] alert The alert in question
    # @param [Array] already_sent_to A list of people that have already received this alert.
    #
    # @return [Array] The list of people that have received this alert.
    def notify(alert, already_sent_to = [], during_runner = nil)

      if usernames.nil? or usernames.empty?
        logger.warn "No usernames found for notification #{list}"
        return
      end

      # Set up a during_runner
      during_runner ||= DuringRunner.new(Time.now, alert, &self.during)

      # Should we notify at all?
      return already_sent_to unless during_runner.now?

      people.collect do |person|
        case person
          when PeopleList
            person.people(during_runner.time)
          when Person
            person
          else
            nil
        end
      end.flatten.compact.uniq.each do |person|
        #
        # A bit of alert de-bouncing.
        #
        if already_sent_to.include?(person.username)
          logger.info("Already sent notification of #{alert} to #{person.username}")
        else
          person.send_alert(level, alert)
          already_sent_to << person.username
        end
      end

      return already_sent_to
    end
   
    # Work out when this notification should next get sent.  Nil will be
    # returned if the alert is not raised.
    #
    # @param [Mauve::Alert] alert The alert in question
    # @return [Time or nil] The time a reminder should get sent, or nil if it
    #   should never get sent again.
    def remind_at_next(alert, during_runner = nil)
      #
      # Don't remind on acknowledgements / clears.
      #
      return nil unless alert.raised?

      #
      # Never remind if every is not set.
      #
      return nil unless every

      # Set up a during_runner
      during_runner ||= DuringRunner.new(Time.now, alert, &self.during)

      if during_runner.now?
        return during_runner.find_next(every)
      else
        return during_runner.find_next()
      end

    end

  end

end

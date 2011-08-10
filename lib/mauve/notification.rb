# encoding: UTF-8
require 'mauve/person'
require 'mauve/notifiers'

module Mauve
  # This class provides an execution context for the code found in 'during'
  # blocks in the configuration file.  This code specifies when an alert
  # should cause notifications to be generated, and can access @time and
  # @alert variables.  There are also some helper methods to provide
  # oft-needed functionality such as hours_in_day.
  #
  # e.g. to send alerts only between 10 and 11 am:
  #
  #   during = Proc.new { @time.hour == 10 }
  #   
  # ... later on ...
  #   
  #   DuringRunner.new(Time.now, my_alert, &during).inside?
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

    def initialize(time, alert=nil, &during)
      raise ArgumentError.new("Must supply time (not #{time.inspect})") unless time.is_a?(Time)
      @time = time
      @alert = alert
      @during = during || Proc.new { true }
      @logger = Log4r::Logger.new "Mauve::DuringRunner"
    end
    
    #
    #
    #
    def now?(t=@time)
      @test_time = t
      res = instance_eval(&@during)
    end

    def find_next(after = 5.minutes)
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

    def hours_in_day(*hours)
      x_in_list_of_y(@test_time.hour, hours.flatten)
    end
    
    def days_in_week(*days)
      x_in_list_of_y(@test_time.wday, days.flatten)
    end
    
    ## Return true if the alert has not been acknowledged within a certain time.
    # 
    def unacknowledged(seconds)
      @alert &&
        @alert.raised? &&
        !@alert.acknowledged? &&
        (@test_time - @alert.raised_at.to_time) > seconds
    end
    
    def x_in_list_of_y(x,y)
      y.any? do |range|
        if range.respond_to?("include?")
          range.include?(x)
        else
          range == x
        end
      end
    end

    def working_hours? 
      @test_time.working_hours?
    end

    # Return true in the dead zone between 3 and 7 in the morning.
    #
    # Nota bene that this is used with different times in the reminder section.
    #
    # @return [Boolean] Whether now is a in the dead zone or not.
    def dead_zone?
      @test_time.dead_zone?
    end

  end
  
  # A Notification is an instruction to notify a list of people, at a
  # particular alert level, on a periodic basis, and optionally under
  # certain conditions specified by a block of code.
  #
  class Notification < Struct.new(:people, :level, :every, :during, :list)

    def to_s
      "#<Notification:of #{people.map { |p| p.username }.join(',')} at level #{level} every #{every}>"
    end
 
    attr_reader :thread_list

    def initialize(people, level)

      self.level = level
      self.every = 300
      self.people = people
    end

    def logger ;  Log4r::Logger.new self.class.to_s ; end

    # Updated code, now takes account of lists of people.
    #
    # @TODO refactor so we can test this more easily.
    #
    # @TODO Make sure that if no notifications is send at all, we log this
    #       as an error so that an email is send to the developers.  Hum, we
    #       could have person.alert_changed return true if a notification was 
    #       send (false otherwise) and add it to a queue.  Then, dequeue till 
    #       we see a "true" and abort.  However, this needs a timeout loop 
    #       around it and we will slow down the whole notificatin since it
    #       will have to wait untill such a time as it gets a true or timeout.
    #       Not ideal.  A quick fix is to make sure that the clause in the 
    #       configuration has a fall back that will send an alert in all cases.
    #
    def notify(alert)

      if people.nil? or people.empty?
        logger.warn "No people found in for notification #{list}"
        return
      end

      # Should we notify at all?
      is_relevant = DuringRunner.new(Time.now, alert, &during).now?

      people.collect do |person|
        case person
          when Person
            person
          when PeopleList
            person.people
          else
            logger.warn "Unable to notify #{person} (unrecognised class #{person.class})"
            []
        end
      end.flatten.uniq.each do |person|
        person.send_alert(level, alert, is_relevant, remind_at_next(alert))
      end

      return nil
    end
    
    def remind_at_next(alert)

      return DuringRunner.new(Time.now, alert, &during).find_next(every) if alert.raised?

      return nil
    end

  end

end

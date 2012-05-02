require 'date'
require 'time'

#
# Extra methods for integer to calculate periods in seconds.
#
class Integer
  # @return [Integer]
  def seconds; self; end
  # @return [Integer] n minutes of seconds
  def minutes; self*60; end
  # @return [Integer] n hours of seconds
  def hours; self*3600; end
  # @return [Integer] n days of seconds
  def days; self*86400; end
  # @return [Integer] n weeks of seconds
  def weeks; self*604800; end
  alias_method :day, :days
  alias_method :hour, :hours
  alias_method :minute, :minutes
  alias_method :week, :weeks
end

#
# Extra methods for Time.
#
class Time
  #
  # Method to work out when something is due, with different classes of hours.
  #
  # @param [Integer] n The number of hours in the future
  # @param [String] type One of wallclock, working, or daytime.
  # 
  # @return [Time]
  #
  def in_x_hours(n, type="wallclock")
    raise ArgumentError, "n must be numeric" unless n.is_a?(Numeric)
    raise ArgumentError, "type must be a string" unless type.is_a?(String)

    t = self.dup

    #
    # Do this in seconds rather than hours
    #
    n = (n*3600).to_i
  
    test = case type
      when "working"
        "working_hours?"
      when "daytime"
        "daytime_hours?"
      else
        "wallclock_hours?"
    end

    step = 3600

    #
    # Work out how much time to subtract now
    #
    while n >= 0
      #
      # If we're currently OK, and we won't be OK after the next step (or
      # vice-versa) decrease step size, and try again
      #
      if (t.__send__(test) != (t+step).__send__(test)) 
        #
        # Unless we're on the smallest step, try a smaller one.
        #
        unless step == 1
          step /= 60

        else
          n -= step if t.__send__(test)
          t += step

          #
          # Set the step size back to an hour
          #
          step = 3600
        end

        next
      end

      #
      # Decrease the time by the step size if we're currently OK.
      #
      n -= step if t.__send__(test)
      t += step
    end
    
    #
    # Substract any overshoot.
    #
    t += n if n < 0

    t
  end

  # Returns the bank_holidays array, or an empty array if bank_holidays hasn't
  # been set.
  #
  #
  def bank_holidays
    @bank_holidays = if defined? Server and Server.instance
      Server.instance.bank_holidays
    else
      @bank_holidays || []
    end
  end

  # Returns an array of ranges of working hours
  #
  #
  def working_hours
    if defined? Configuration and Configuration.current
      Configuration.current.working_hours
    else
      [9.0...17.0]
    end
  end
  
  def dead_zone
    if defined? Configuration and Configuration.current
      Configuration.current.working_hours
    else
      [3.0...7.0]
    end
  end
  
  def daytime_hours
    if defined? Configuration and Configuration.current
      Configuration.current.working_hours
    else
      [8.0...20.0]
    end
  end

  # This relies on bank_holidays being set.
  #
  def bank_holiday?
    today = Date.new(self.year, self.month, self.day)
    self.bank_holidays.any?{|bh| bh == today}
  end

  # Test to see if we're in working hours. The working day is from 8.30am until
  # 17:00
  #
  # @return [Boolean]
  def working_hours?
    (1..5).include?(self.wday) and
    self.working_hours.any?{|r| r.include?(self.hour.to_f + self.min.to_f/60.0)} and
    !self.bank_holiday?
  end

  # Test to see if it is currently daytime.  The daytime day is 14 hours long
  #
  # @return [Boolean]
  def daytime_hours?
    self.daytime_hours.any?{|r| r.include?(self.hour.to_f + self.min.to_f/60.0)}
  end
  
  # We're always in wallclock hours
  #
  # @return [true]
  def wallclock_hours?
    true
  end
  
  # Test to see if we're in the DEAD ZONE!   This is from 3 - 6am every day.
  #
  # @return [Boolean]
  def dead_zone?
    self.dead_zone.any?{|r| r.include?(self.hour.to_f + self.min.to_f/60.0)}
  end
  
  # Format the time as a string, relative to +now+
  #
  # @param [Time] now The time we're using as a base
  # @raise [ArgumentError] if +now+ is not a Time
  # @return [String]
  #
  def to_s_relative(now = Time.now)
    #
    # Make sure now is the correct class
    #
    now = now if now.is_a?(DateTime)

    raise ArgumentError, "now must be a Time" unless now.is_a?(Time)

    diff = (now.to_f - self.to_f).round.to_i.abs
    n = nil

    if diff < 120
      n = nil
    elsif diff < 3600
      n = diff/60.0
      unit = "minute"
    elsif diff < 172800
      n = diff/3600.0
      unit = "hour"
    elsif diff < 5184000 
      n = diff/86400.0
      unit = "day"
    else
      n = diff/2592000.0
      unit = "month"
    end

    unless n.nil?
      n = n.round.to_i 
      unit += "s" if n != 1
    end

    # The FUTURE
    if self > now
      return "shortly" if n.nil?
      "in #{n} #{unit}"
    else
      return "just now" if n.nil?
      "#{n} #{unit}"+" ago"
    end
  end

  def to_s_human
    _now = Time.now

    if _now.strftime("%F") == self.strftime("%F")  
      self.strftime("%R today")

    # Tomorrow is in 24 hours
    elsif (_now + 86400).strftime("%F") == self.strftime("%F")
      self.strftime("%R tomorrow")

    # Yesterday is in 24 ago
    elsif (_now - 86400).strftime("%F") == self.strftime("%F")
      self.strftime("%R yesterday")

    # Next week starts in 6 days.
    elsif self > _now and self < (_now + 86400 * 6)
      self.strftime("%R on %A")

    else
      self.strftime("%R on %a %d %b %Y")

    end

  end

end

#module Mauve
#  class Time < Time
#
#    def to_s
#      self.iso8601
#    end
#
#    def to_mauvetime
#      self
#    end
#    
#  end
#end

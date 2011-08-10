require 'date'
require 'time'


# Seconds, minutes, hours, days, and weeks... More than that, we 
# really should not need it.
class Integer
  def seconds; self; end
  def minutes; self*60; end
  def hours; self*3600; end
  def days; self*86400; end
  def weeks; self*604800; end
  alias_method :day, :days
  alias_method :hour, :hours
  alias_method :minute, :minutes
  alias_method :week, :weeks
end

class Date
  def to_time
    Time.parse(self.to_s)
  end
end

class DateTime
  def to_time
    Time.parse(self.to_s)
  end

  def to_s_relative(*args)
    self.to_time.to_s_relative(*args)
  end

  def to_s_human
    self.to_time.to_s_human
  end

  def in_x_hours(*args)
    self.to_time.in_x_hours(*args)
  end

end

class Time
  def in_x_hours(n, type="wallclock")
    t = self.dup
    #
    # Do this in minutes rather than hours
    #
    n = n.to_i*3600
  
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

  #
  # The working day is from 8.30am until 17:00
  #
  def working_hours?
    (1..5).include?(self.wday) and ((9..16).include?(self.hour) or  (self.hour == 8 && self.min >= 30))
  end

  #
  # The daytime day is 14 hours long
  #
  def daytime_hours?
    (8..21).include?(self.hour)
  end
  
  #
  # The daytime day is 14 hours long
  #
  def wallclock_hours?
    true
  end
  
  #
  # In the DEAD ZONE! 
  #
  def dead_zone?
    (3..6).include?(self.hour)
  end
    
  def to_s_relative(now = Time.now)
    #
    # Make sure now is the correct class
    #
    now = now.to_time if now.is_a?(DateTime)

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

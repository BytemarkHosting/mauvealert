require 'logger'
require 'time'

module Mauve
  # A fake Time, which we use in testing.  Time#now returns the same value every
  # time, unless we call Time#advance which alters the value of 'now' by a
  # given number of seconds.  There is a simple pass-through for other methods.
  #
  class Time
    class << self
      def reset_to_midnight
        @now = Time.parse("00:00")
        Log.debug "Test time reset to #{@now}"
      end
    
      def now
        reset_to_midnight unless @now
        @now
      end
      
      def advance(seconds)
        @now += seconds
        Log.debug "Test time advanced by #{seconds} to #{@now}, kicking Mauve::Timers"
        Timers.restart_and_then_wait_until_idle
        @now
      end
      
      def at(*a)
        ::Time.at(*a)
      end
      
      def parse(*a)
        ::Time.parse(*a)
      end
    end
  end
end


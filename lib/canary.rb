# encoding: UTF-8
require 'logger'

# A little canary class to make sure that threads are are overloaded.
class Canary

  # Accessor.
  attr_reader :sleep_time

  # Accessor.
  attr_reader :threshold

  # Default constructor.
  def initialize (st=1, log=nil)
    if Float != st.class and Fixnum != st.class
      raise ArgumentError.new(
        "Expected either Fixnum or Float for time to sleep, got #{st.class}.") 
    end
    @sleep_time = st
    @threshold = (0.05 * @sleep_time) + @sleep_time
    @logger = log
  end

  # Runs the check.
  def run
    loop do
      self.do_test()
    end
  end

  def do_test
    time_start = Time.now
    sleep(@sleep_time)
    time_end = Time.now
    time_elapsed = (time_end - time_start).abs
    if @threshold < time_elapsed
      @logger.fatal("Time elapsed is #{time_elapsed} > #{@threshold} therefore Canary is dead.")
      return false
    else
      @logger.debug("Time elapsed is #{time_elapsed} < #{@threshold} therefore Canary is alive.")
      return true
    end
  end

  # Starts a canary in a thread.
  def self.start (st=1, log=nil)
    #Thread.abort_on_exception = true
    thr = Thread.new() do
      Thread.current[:name] = "Canary Thread"
      twiti = Canary.new(st, log)
      twiti.run()
    end
  end

end

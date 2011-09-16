require 'thread'
require 'singleton'

module Mauve

  #
  # This is a class to wrap our threads that have processing loops.
  #
  # The thread is kept in a wrapper to allow it to be frozen and thawed at
  # convenient times.
  #
  class MauveThread

    #
    # The sleep interval between runs of the main loop.  Defaults to 5 seconds.
    #
    attr_reader :poll_every

    #
    # Set the thread up
    #
    def initialize
      @thread = nil
    end

    # @return [Log4r::Logger]
    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s) 
    end

    # Set the sleep interval between runs of the main loop.  This can be
    # anything greater than or equal to zero.  If a number less than zero gets
    # entered, it will be increased to zero.
    #
    # @param [Numeric] i The number of seconds to sleep
    # @raise [ArgumentError] If +i+ is not numeric
    # @return [Numeric] 
    #
    def poll_every=(i)
      raise ArgumentError.new("poll_every must be numeric") unless i.is_a?(Numeric)
      # 
      # Set the minimum poll frequency.
      #
      if i.to_f < 0
        logger.debug "Increasing thread polling interval to 0s from #{i}"
        i = 0 
      end

      @poll_every = i
    end

    # This determines if a thread should stop
    # 
    # @return [Boolean]
    def should_stop?
      [:freezing, :stopping].include?(self.state)
    end

    # This is the current state of the thread.  It can be one of
    #   [:stopped, :starting, :started, :freezing, :frozen, :stopping, :killing, :killed]
    # 
    # If the thread is not alive it will be +:stopped+.
    #
    # @return [Symbol] One of [:stopped, :starting, :started, :freezing,
    #   :frozen, :stopping, :killing, :killed]
    def state
      if self.alive?
        @thread.key?(:state) ?  @thread[:state] : :unknown
      else
        :stopped
      end
    end

    # This sets the state of a thread.  It also records the last time the
    # thread changed status.
    # 
    # @param [Symbol] s One of [:stopped, :starting, :started, :freezing,
    #   :frozen, :stopping, :killing, :killed] 
    # @raise [ArgumentError] if +s+ is not a valid symbol or the thread is not
    #   ready
    # @return [Symbol] the current thread state.
    #
    def state=(s)
      raise ArgumentError, "Bad state for mauve_thread #{s.inspect}" unless [:stopped, :starting, :started, :freezing, :frozen, :stopping, :killing, :killed].include?(s)
      raise ArgumentError, "Thread not ready yet." unless @thread.is_a?(Thread)

      unless @thread[:state] == s
        @thread[:state] = s
        @thread[:last_state_change] = Time.now
        logger.debug(s.to_s.capitalize) 
      end

      @thread[:state]
    end

    # This returns the time of the last state change, or nil if the thread is dead.
    #
    # @return [Time or Nilclass]
    def last_state_change
      if self.alive? and @thread.key?(:last_state_change)
        return @thread[:last_state_change]
      else
        return nil
      end
    end

    # This asks the thread to freeze at the next opportunity.
    #
    def freeze
      self.state = :freezing
      
      20.times { Kernel.sleep 0.2 ; break if @thread.stop? }

      logger.warn("Thread has not frozen!") unless @thread.stop?
    end

    # This returns true if the thread has frozen successfully.
    #
    # @return [Boolean]
    def frozen?
      self.stop? and self.state == :frozen
    end

    # This starts the thread.  It wakes it up if it is alive, or starts it from
    # fresh if it is dead.
    #
    def run
      if self.alive? 
        # Wake up if we're stopped.
        if self.stop?
          @thread.wakeup 
        end
      else
        @logger = nil
        Thread.new do
          run_thread { main_loop } 
        end
      end
    end

    alias start run
    alias thaw  run

    # This checks to see if the thread is alive
    #
    # @return [Boolean]
    def alive?
      @thread.is_a?(Thread) and @thread.alive?
    end

    # This checks to see if the thread is stopped
    #
    # @return [Boolean]
    def stop?
      self.alive? and @thread.stop?
    end

    # This joins the thread
    #
    def join
      @thread.join if @thread.is_a?(Thread)
    end

#    def raise(ex)
#      @thread.raise(ex)
#    end

    # This returns the thread's backtrace
    #
    # @return [Array or Nilclass]
    def backtrace
      @thread.backtrace if @thread.is_a?(Thread)
    end

    # This restarts the thread
    #
    #
    def restart
      self.stop
      self.start
    end
    
    # This stops the thread
    #
    #
    def stop
      self.state = :stopping

      10.times do 
        break unless self.alive?
        Kernel.sleep 1 if self.alive? 
      end

      #
      # OK I've had enough now.
      #
      self.kill if self.alive?

      self.join 
    end

    alias exit stop

    # This kills the thread -- faster than #stop
    #
    def kill
      self.state = :killing
      @thread.kill
      self.state = :killed
    end

    # This returns the thread itself.
    # 
    # @return [Thread] 
    def thread
      @thread
    end


    private

    # This is the main run loop for the thread.  In here are all the calls
    # allowing use to freeze and thaw the thread neatly.
    #
    # This thread will run untill the thread state is changed to :stopping.
    #
    def run_thread(interval = 5.0)
      #
      # Good to go.
      #
      @thread = Thread.current
      self.state = :starting

      @poll_every ||= interval
      #
      # Make sure we get a number.
      #
      @poll_every = 5 unless @poll_every.is_a?(Numeric)

      rate_limit = 0.1

      while self.state != :stopping do

        self.state = :started if self.state == :starting

        #
        # Schtop!
        #
        if self.state == :freezing
          self.state = :frozen
          Thread.stop
          self.state = :started
        end

        yield_start = Time.now.to_f

        yield

        #
        # Ah-ha! Sleep with a break clause.  Make sure we poll every @poll_every seconds.
        #
        ((@poll_every.to_f - Time.now.to_f + yield_start.to_f)/rate_limit).
          round.to_i.times do

          break if self.should_stop?

          #
          # This is a rate-limiting step
          #
          Kernel.sleep rate_limit
        end
      end

      self.state = :stopped
    end

  end

end


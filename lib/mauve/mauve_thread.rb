require 'thread'
require 'singleton'

module Mauve

  #
  # This is a class to wrap our threads that have processing loops.
  #
  class MauveThread

    #
    # Set the thread up
    #
    def initialize
      @thread = nil
      @last_polled_at = nil
    end

    # @return [Log4r::Logger]
    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s) 
    end

    # This determines if a thread should stop
    # 
    # @return [Boolean]
    def should_stop?
      self.state == :stopping
    end

    # This is the current state of the thread.  It can be one of
    #   [:stopped, :starting, :started, :stopping, :killing, :killed]
    # 
    # If the thread is not alive it will be +:stopped+.
    #
    # @return [Symbol] One of [:stopped, :starting, :started, :stopping, :killing, :killed]
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
    # @param [Symbol] s One of [:stopped, :starting, :started, :stopping, :killing, :killed] 
    # @raise [ArgumentError] if +s+ is not a valid symbol or the thread is not
    #   ready
    # @return [Symbol] the current thread state.
    #
    def state=(s)
      raise ArgumentError, "Bad state for mauve_thread #{s.inspect}" unless [:stopped, :starting, :started, :stopping, :killing, :killed].include?(s)
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

    #
    # Returns the time the thread loop was last run, or nil if it has never run.
    #
    def last_polled_at
      @last_polled_at
    end

    private

    # This is the main run loop for the thread.  
    #
    # This thread will run untill the thread state is changed to :stopping.
    #
    def run_thread
      #
      # Good to go.
      #
      @thread = Thread.current
      self.state = :starting

      while self.state != :stopping do
        self.state = :started
        @last_polled_at = Time.now

        yield

        #
        # This is a little sleep to stop cpu hogging.
        #
        Kernel.sleep 0.001 
      end

      self.state = :stopped
    end

  end

end


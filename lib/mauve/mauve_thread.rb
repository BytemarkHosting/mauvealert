require 'thread'
require 'singleton'

module Mauve

  class MauveThread

    attr_reader :poll_every

    def initialize
      @thread = nil
    end

    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s) 
    end

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

    def run_thread(interval = 5.0)
      #
      # Good to go.
      #
      @thread = Thread.current
      self.state = :starting

      @poll_every ||= interval

      sleep_loops = (@poll_every.to_f / 0.1).round.to_i
      sleep_loops = 1 if sleep_loops.nil? or sleep_loops < 1

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

        yield

        #
        # Ah-ha! Sleep with a break clause.
        #
        sleep_loops.times do

          break if self.should_stop?

          #
          # This is a rate-limiting step
          #
          Kernel.sleep 0.1
        end
      end

      self.state = :stopped
    end

    def should_stop?
      [:freezing, :stopping].include?(self.state)
    end

    def state
      if self.alive?
        @thread.key?(:state) ?  @thread[:state] : :unknown
      else
        :stopped
      end
    end

    def state=(s)
      raise "Bad state for mauve_thread #{s.inspect}" unless [:stopped, :starting, :started, :freezing, :frozen, :stopping, :killing, :killed].include?(s)
      raise "Thread not ready yet." unless @thread.is_a?(Thread)

      unless @thread[:state] == s
        @thread[:state] = s
        @thread[:last_state_change] = Time.now
        logger.debug(s.to_s.capitalize) 
      end

      @thread[:state]
    end

    def last_state_change
      if self.alive? and @thread.key?(:last_state_change)
        return @thread[:last_state_change]
      else
        return nil
      end
    end

    def freeze
      self.state = :freezing
      
      20.times { Kernel.sleep 0.2 ; break if @thread.stop? }

      logger.warn("Thread has not frozen!") unless @thread.stop?
    end

    def frozen?
      self.stop? and self.state == :frozen
    end

    def run
      if self.alive? 
        # Wake up if we're stopped.
        if self.stop?
          @thread.wakeup 
        end
      else
        @logger = nil
        Thread.new do
          self.run_thread { self.main_loop } 
        end
      end
    end

    alias start run
    alias thaw  run

    def alive?
      @thread.is_a?(Thread) and @thread.alive?
    end

    def stop?
      self.alive? and @thread.stop?
    end

    def join(ok_exceptions=[])
      @thread.join if @thread.is_a?(Thread)
    end

#    def raise(ex)
#      @thread.raise(ex)
#    end

    def backtrace
      @thread.backtrace if @thread.is_a?(Thread)
    end

    def restart
      self.stop
      self.start
    end
    
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

    def kill
      self.state = :killing
      @thread.kill
      self.state = :killed
    end

    def thread
      @thread
    end

  end

end


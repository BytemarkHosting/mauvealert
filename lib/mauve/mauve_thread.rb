require 'thread'
require 'singleton'

module Mauve

  class MauveThread

    attr_reader :state, :poll_every

    def initialize
      @thread = nil
      @state = :stopped
    end

    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s) 
    end

    def poll_every=(i)
      raise ArgumentError.new("poll_every must be numeric") unless i.is_a?(Numeric)
      @poll_every = i
    end

    def run_thread(interval = 0.1)
      #
      # Good to go.
      #
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

    def state=(s)
      raise "Bad state for mauve_thread #{s.inspect}" unless [:stopped, :starting, :started, :freezing, :frozen, :stopping, :killing, :killed].include?(s)
      unless @state == s
        @state = s
        logger.debug(s.to_s.capitalize) 
      end
    end

    def freeze
      self.state = :freezing
      
      20.times { Kernel.sleep 0.1 ; break if @thread.stop? }

      logger.debug("Thread has not frozen!") unless @thread.stop?
    end

    def frozen?
      self.stop? and self.state == :frozen
    end

    def run
      if self.alive? 
        if self.stop?
          @thread.wakeup 
        end
      else
        @logger = nil
        self.state = :starting
        @thread = Thread.new{ self.run_thread { self.main_loop } }
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


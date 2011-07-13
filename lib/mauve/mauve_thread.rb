require 'thread'
require 'singleton'

module Mauve

  class MauveThread

    def initialize
      @thread = nil
    end

    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s) 
    end

    def run_thread(interval = 0.1)
      #
      # Good to go.
      #
      @frozen = false
      @stop = false

      logger.debug("Started")

      @sleep_interval ||= interval

      while !@stop do
        #
        # Schtop!
        #
        if @frozen
          logger.debug("Frozen")
          Thread.stop
          logger.debug("Thawed")
        end

        yield

        next if self.should_stop?

        Kernel.sleep(@sleep_interval)
      end

      logger.debug("Stopped")
    end

    def should_stop?
      @frozen or @stop
    end

    def freeze
      logger.debug("Freezing") 

      @frozen = true

      20.times { Kernel.sleep 0.1 ; break if @thread.stop? }

      logger.debug("Thread has not frozen!") unless @thread.stop?
    end

    def frozen?
      defined? @frozen and @frozen and @thread.stop?
    end

    def thaw
      logger.debug("Thawing")
      @frozen = false
      @thread.wakeup if @thread.stop?
    end

    def start
      @logger = nil
      logger.debug("Starting")
      @stop   = false
      @thread = Thread.new{ self.run_thread { self.main_loop } }
    end
    
    def run
      if self.alive?
        self.thaw
      else
        self.start
      end
    end

    def alive?
      @thread.is_a?(Thread) and @thread.alive?
    end

    def stop?
      @thread.is_a?(Thread) and @thread.stop?
    end

    def join(ok_exceptions=[])
      @thread.join if @thread.is_a?(Thread)
    end

    def raise(ex)
      @thread.raise(ex)
    end

    def backtrace
      @thread.backtrace if @thread.is_a?(Thread)
    end

    def restart
      self.stop
      self.start
    end
    
    def stop
      logger.debug("Stopping")

      @stop = true

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
      logger.debug("Killing")
      @frozen = true
      @thread.kill
      logger.debug("Killed")
    end

    def thread
      @thread
    end

  end

end


# encoding: UTF-8
require 'yaml'
require 'socket'
# require 'mauve/datamapper'
require 'mauve/proto'
require 'mauve/alert'
require 'mauve/history'
require 'mauve/mauve_thread'
require 'mauve/mauve_time'
require 'mauve/timer'
require 'mauve/udp_server'
require 'mauve/pop3_server'
require 'mauve/processor'
require 'mauve/http_server'
require 'mauve/heartbeat'
require 'log4r'

module Mauve

  class Server < MauveThread

    #
    # This is the order in which the threads should be started.
    #
    THREAD_CLASSES = [UDPServer, HTTPServer, Pop3Server, Processor, Timer, Notifier, Heartbeat]

    attr_reader :hostname, :database, :initial_sleep
    attr_reader   :packet_buffer, :notification_buffer, :started_at

    include Singleton

    def initialize
      super
      @hostname    = "localhost"
      @database    = "sqlite3::memory:"
      
      @started_at = Time.now
      @initial_sleep = 300

      #
      # Keep these queues here to prevent a crash in a subthread losing all the
      # subsquent things in the queue.
      #
      @packet_buffer       = []
      @notification_buffer = []

      #
      # Set up a blank config.
      #
      Configuration.current = Configuration.new if Mauve::Configuration.current.nil?
    end

    def hostname=(h)
      raise ArgumentError, "hostname must be a string" unless h.is_a?(String)
      @hostname = h
    end

    def database=(d)
      raise ArgumentError, "database must be a string" unless d.is_a?(String)
      @database = d
    end

    def initial_sleep=(s)
      raise ArgumentError, "initial_sleep must be numeric" unless s.is_a?(Numeric)
      @initial_sleep = s
    end

    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s)
    end

    def setup
      #
      #
      #
      @packet_buffer       = []
      @notification_buffer = []

      DataMapper.setup(:default, @database)
      # DataMapper.logger = Log4r::Logger.new("Mauve::DataMapper") 

      #
      # Update any tables.
      #
      Mauve.constants.each do |c| 
        next if %w(AlertEarliestDate).include?(c)
        m = Mauve.const_get(c)
        m.auto_upgrade! if m.respond_to?("auto_upgrade!")
        # 
        # Don't want to use automigrate, since this trashes the tables.
        #
        # m.auto_migrate! if m.respond_to?("auto_migrate!")
      end

      Mauve::AlertEarliestDate.create_view!

      return nil
    end

    def start
      self.state = :starting

      self.setup
      
      self.run_thread { self.main_loop }
    end

    alias run start 

    def main_loop
      thread_list = Thread.list 

      thread_list.delete(Thread.current)

      THREAD_CLASSES.each do |klass|
        #
        # No need to double check ourselves.
        #
        thread_list.delete(klass.instance.thread)

        # 
        # Do nothing if we're frozen or supposed to be stopping or still alive!
        #
        next if self.should_stop? or klass.instance.alive?

        # 
        # ugh something is beginnging to smell.
        #
        begin
          klass.instance.join
        rescue StandardError => ex
          logger.error "Caught #{ex.to_s} whilst checking #{klass} thread"
          logger.debug ex.backtrace.join("\n")
        end

        #
        # (re-)start the klass.
        #
        klass.instance.start unless self.should_stop?
      end

      #
      # Now do the same with other threads.  However if these ones crash, the
      # server has to stop, as there is no method to restart them.
      #
      thread_list.each do |t|

        next if self.should_stop? or t.alive?

        begin
          t.join
        rescue StandardError => ex
          logger.fatal "Caught #{ex.to_s} whilst checking threads"
          logger.debug ex.backtrace.join("\n")
          self.stop
          break
        end

      end
    end
    
    def stop
      if self.state == :stopping
        # uh-oh already told to stop.
        logger.error "Stop already called.  Killing self!"
        Kernel.exit 1 
      end

      self.state = :stopping

      THREAD_CLASSES.each do |klass|
        klass.instance.stop unless klass.instance.nil?
      end
      
      thread_list = Thread.list 
      thread_list.delete(Thread.current)

      thread_list.each do |t|
        t.exit
      end      

      self.state = :stopped
    end


    class << self

      #
      # BUFFERS
      #
      # These methods are here, so that if the threads that are popping and
      # processing them crash, the buffer itself is not lost with the thread.
      #

      #
      # These methods pop things on and off the packet_buffer
      #
      def packet_enq(a)
        instance.packet_buffer.push(a)
      end

      def packet_deq
        instance.packet_buffer.shift
      end

      def packet_buffer_size
        instance.packet_buffer.size
      end

      alias packet_push packet_enq
      alias packet_pop  packet_deq
      
      #
      # These methods pop things on and off the notification_buffer
      #
      def notification_enq(a)
        instance.notification_buffer.push(a)
      end

      def notification_deq
        instance.notification_buffer.shift
      end

      def notification_buffer_size
        instance.notification_buffer.size
      end

      alias notification_push notification_enq
      alias notification_pop  notification_deq

    end

  end

end

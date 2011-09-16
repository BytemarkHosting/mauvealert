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
require 'mauve/configuration'
require 'log4r'

module Mauve

  class Server < MauveThread

    #
    # This is the order in which the threads should be started.
    #
    THREAD_CLASSES = [UDPServer, HTTPServer, Pop3Server, Processor, Timer, Notifier, Heartbeat]

    attr_reader   :hostname, :database, :initial_sleep
    attr_reader   :packet_buffer, :notification_buffer, :started_at

    include Singleton

    # Initialize the Server, setting up a blank configuration if no
    # configuration has been created already.
    #
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

    # Set the hostname of this Mauve instance.
    #
    # @param [String] h The hostname
    def hostname=(h)
      raise ArgumentError, "hostname must be a string" unless h.is_a?(String)
      @hostname = h
    end

    # Set the database
    #
    # @param [String] d The database
    def database=(d)
      raise ArgumentError, "database must be a string" unless d.is_a?(String)
      @database = d
    end
    
    # Set the sleep period during which notifications about old alerts are
    # suppressed.
    #
    # @param [Integer] s The initial sleep period.
    def initial_sleep=(s)
      raise ArgumentError, "initial_sleep must be numeric" unless s.is_a?(Numeric)
      @initial_sleep = s
    end

    # Test to see if we should suppress alerts because we're in the initial sleep period
    #
    # @return [Boolean]
    def in_initial_sleep?
      Time.now < self.started_at + self.initial_sleep
    end

    # return [Log4r::Logger]
    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s)
    end

    # This sorts out the Server.  It empties the notification and packet
    # buffers.  It configures and migrates the database.
    #  
    # @return [NilClass]
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

      AlertHistory.migrate!
      AlertEarliestDate.create_view!

      return nil
    end

    # This sets up the server, and then starts the main loop.
    #
    def start
#      self.state = :starting

      setup
      
      run_thread { main_loop }
    end

    alias run start 
    
    #
    # This stops the main loop, and all the threads that are defined in THREAD_CLASSES above.
    #
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

    private

    def main_loop
      thread_list = Thread.list 

      thread_list.delete(Thread.current)

      #
      # Check buffer sizes
      #
      if self.class.notification_buffer_size >= 10
        logger.warn "Notification buffer has #{self.class.notification_buffer_size} messages in it"
      end
      
      if self.class.packet_buffer_size >= 100
        logger.warn "Packet buffer has #{self.class.packet_buffer_size} updates in it"
      end


      THREAD_CLASSES.each do |klass|
        #
        # No need to double check ourselves.
        #
        thread_list.delete(klass.instance.thread)

        #
        # Make sure that if the thread is frozen, that we've not been frozen for too long.
        #
        if klass.instance.state != :started and klass.instance.last_state_change.is_a?(Time) and klass.instance.last_state_change < (Time.now - 2.minutes)
          logger.warn "#{klass} has been #{klass.instance.state} since #{klass.instance.last_state_change}. Killing and restarting."
          klass.instance.stop
        end

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
    

    class << self

      #
      # BUFFERS
      #
      # These methods are here, so that if the threads that are popping and
      # processing them crash, the buffer itself is not lost with the thread.
      #

      # Push a packet onto the back of the +packet_buffer+
      # 
      # @param [String] a Packet from the UDP server
      def packet_enq(a)
        instance.packet_buffer.push(a)
      end

      # Shift a packet off the front of the +packet buffer+
      #
      # @return [String] the oldest UDP packet
      def packet_deq
        instance.packet_buffer.shift
      end

      # Returns the current length of the +packet_buffer+
      #
      # @return [Integer}
      def packet_buffer_size
        instance.packet_buffer.size
      end

      alias packet_push packet_enq
      alias packet_pop  packet_deq
      
      # Push a notification on to the back of the +notification_buffer+
      #
      # @param [Array] a Notification array, consisting of a Person and the args to Mauve::Person#send_alert
      def notification_enq(a)
        instance.notification_buffer.push(a)
      end

      # Shift a notification off the front of the +notification_buffer+
      #
      # @return [Array] Notification array, consisting of a Person and the args to Mauve::Person#send_alert
      def notification_deq
        instance.notification_buffer.shift
      end

      # Return the current length of the +notification_buffer+
      #
      # @return [Integer]
      def notification_buffer_size
        instance.notification_buffer.size
      end

      alias notification_push notification_enq
      alias notification_pop  notification_deq

    end

  end

end

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
require 'mauve/processor'
require 'mauve/http_server'
require 'log4r'

module Mauve

  class Server 

    DEFAULT_CONFIGURATION = {
      :ip => "127.0.0.1",
      :port => 32741,
      :database => "sqlite3:///./mauvealert.db",
      :log_file => "stdout",
      :log_level => 1,
      :transmission_cache_expire_time => 600
    }


    #
    # This is the order in which the threads should be started.
    #
    THREAD_CLASSES = [UDPServer, HTTPServer, Processor, Timer, Notifier]

    attr_accessor :web_interface
    attr_reader   :stopped_at, :started_at, :initial_sleep, :packet_buffer, :notification_buffer

    include Singleton

    def initialize
      # Set the logger up

      # Sleep time between pooling the @buffer buffer.
      @sleep = 1

      @frozen     = false
      @stop       = false

      @stopped_at = MauveTime.now
      @started_at = MauveTime.now
      @initial_sleep = 300

      #
      # Keep these queues here to prevent a crash in a subthread losing all the
      # subsquent things in the queue.
      #
      @packet_buffer       = []
      @notification_buffer = []

      @config = DEFAULT_CONFIGURATION
    end

    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s)
    end

    def configure(config_spec = nil)
      #
      # Update the configuration
      #
      if config_spec.nil?
        # Do nothing
      elsif config_spec.kind_of?(String) and File.exists?(config_spec)
        @config.update(YAML.load_file(config_spec))
      elsif config_spec.kind_of?(Hash)
        @config.update(config_spec)
      else
        raise ArgumentError.new("Unknown configuration spec "+config_spec.inspect)
      end

      #
      DataMapper.setup(:default, @config[:database])
      # DataObjects::Sqlite3.logger = Log4r::Logger.new("Mauve::DataMapper") 

      #
      # Update any tables.
      #
      Alert.auto_upgrade!
      AlertChanged.auto_upgrade!
      History.auto_upgrade!
      Mauve::AlertEarliestDate.create_view!

      #
      # Work out when the server was last stopped
      #
      # topped_at = self.last_heartbeat 
    end
   
    def last_heartbeat
      #
      # Work out when the last update was
      #
      [ Alert.last(:order => :updated_at.asc), 
        AlertChanged.last(:order => :updated_at.asc) ].
        reject{|a| a.nil? or a.updated_at.nil? }.
        collect{|a| a.updated_at.to_time}.
        sort.
        last
    end

    def freeze
      @frozen = true
    end

    def thaw
      @thaw = true
    end

    def stop
      if @stop
        logger.debug("Stop already called!")
        return
      end

      @stop = true

      thread_list = Thread.list 

      thread_list.delete(Thread.current)

      THREAD_CLASSES.each do |klass|
        thread_list.delete(klass.instance)
        klass.instance.stop unless klass.instance.nil?
      end

      thread_list.each do |t|
        t.exit
      end      

      logger.info("All threads stopped")
    end

    def run
      @stop = false

      loop do
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
          next if @frozen or @stop or klass.instance.alive?

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
          klass.instance.start unless @stop
        end

        #
        # Now do the same with other threads.  However if these ones crash, the
        # server has to stop, as there is no method to restart them.
        #
        thread_list.each do |t|

          next if t.alive?

          begin
            t.join
          rescue StandardError => ex
            logger.fatal "Caught #{ex.to_s} whilst checking threads"
            logger.debug ex.backtrace.join("\n")
            self.stop
            break
          end

        end

        break if @stop

        sleep 1
      end
      logger.debug("Thread stopped")
    end

    alias start run

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

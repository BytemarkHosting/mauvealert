# encoding: UTF-8

require 'mauve/mauve_thread'

module Mauve

  #
  # This class is a singlton thread which pops updates off the
  # Server#packet_buffer and processes them as alert updates.
  #
  # It is responsible for de-bouncing updates, i.e. ones with duplicate
  # transmission IDs.
  #
  class Processor < MauveThread

    include Singleton

    # This is the time after which transmission IDs are expired.
    #
    attr_reader :transmission_cache_expire_time

    # Initialize the processor
    #
    def initialize
      super
      #
      # Set up the transmission id cache
      #
      @transmission_id_cache = {}
      @transmission_cache_expire_time = 300
      @transmission_cache_checked_at = Time.now
    end

    # @return [Log4r::Logger]
    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s)
    end

    # Set the expiry time
    #
    # @param [Integer] i The number of seconds after which transmission IDs are considered unseen.
    # @raise [ArgumentError] If +i+ is not an Integer
    def transmission_cache_expire_time=(i)
      raise ArgumentError, "transmission_cache_expire_time must be an integer" unless i.is_a?(Integer)
      @transmission_cache_expire_time = i
    end

    # This expries the transmission cache
    #
    #
    def expire_transmission_id_cache
      now = Time.now
      #
      # Only check once every minute.
      #
      return unless (now - @transmission_cache_checked_at) > 60

      to_delete = []

      @transmission_id_cache.each do |tid, received_at|
        to_delete << tid if (now - received_at) > @transmission_cache_expire_time
      end

      to_delete.each do |tid|
        @transmission_id_cache.delete(tid)
      end
      
      @transmission_cache_checked_at = now
    end

    # This stops the processor, making sure all pending updates are saved.
    #
    def stop
      super

      # 
      # flush the queue
      #
      main_loop
    end

    private

    # This is the main loop that does the processing.
    #
    def main_loop
      
      sz = Server.packet_buffer_size

      sz.times do
        Timer.instance.freeze if Timer.instance.alive? and !Timer.instance.frozen?

        #
        # Hmm.. timer not frozen.
        #
        break unless Timer.instance.frozen?

        data, client, received_at = Server.packet_pop

        #
        # Uh-oh.  Nil data?  That's craaaazy
        #
        next if data.nil?
        

        # logger.debug("Got #{data.inspect} from #{client.inspect}")

        ip_source = "#{client[3]}"
        update = Proto::AlertUpdate.new

        begin
          update.parse_from_string(data)
  
          if @transmission_id_cache[update.transmission_id.to_s]
            logger.debug("Ignoring duplicate transmission id #{update.transmission_id}")
            #
            # Continue with next packet.
            #
            next
          end

          logger.debug "Update #{update.transmission_id} sent at #{update.transmission_time} received at #{received_at.to_i} from "+
            "'#{update.source}'@#{ip_source} alerts #{update.alert.length}"

          Alert.receive_update(update, received_at, ip_source)

        rescue Protobuf::InvalidWireType, 
               NotImplementedError, 
               DataObjects::IntegrityError => ex

          logger.error "#{ex} (#{ex.class}) while parsing #{data.length} bytes "+
            "starting '#{data[0..15].inspect}' from #{ip_source}"

          logger.debug ex.backtrace.join("\n")

        ensure
          @transmission_id_cache[update.transmission_id.to_s] = Time.now
        end

      end

    ensure
      #
      # Thaw the timer 
      #
      Timer.instance.thaw if Timer.instance.frozen?
    end

  end   

end


# encoding: UTF-8

require 'mauve/mauve_thread'

module Mauve

  class Processor < MauveThread

    include Singleton

    attr_accessor :transmission_cache_expire_time, :sleep_interval

    def initialize
      # Set the logger up
      @logger = Log4r::Logger.new(self.class.to_s)

      #
      # Set up the transmission id cache
      #
      @transmission_id_cache = {}
      @transmission_cache_expire_time = 300
      @sleep_interval = 1
    end

    def main_loop

      sz = Server.packet_buffer_size

      return if sz == 0
  
      Timer.instance.freeze unless Timer.instance.frozen?

      logger.info("Buffer has #{sz} packets waiting...")

      #
      # Only do the loop a maximum of 10 times every @sleep_interval seconds
      #

      (sz > 10 ? 10 : sz).times do
        data, client, received_at = Server.packet_pop

        @logger.debug("Got #{data.inspect} from #{client.inspect}")

        ip_source = "#{client[3]}:#{client[1]}"
        update = Proto::AlertUpdate.new

        begin
          update.parse_from_string(data)
  
          if @transmission_id_cache[update.transmission_id.to_s]
            @logger.debug("Ignoring duplicate transmission id #{update.transmission_id}")
            #
            # Continue with next packet.
            #
            next
          end

          @logger.debug "Update #{update.transmission_id} sent at #{update.transmission_time} from "+
            "'#{update.source}'@#{ip_source} alerts #{update.alert.length}"

          Alert.receive_update(update, received_at)

        rescue Protobuf::InvalidWireType, 
               NotImplementedError, 
               DataObjects::IntegrityError => ex

          @logger.error "#{ex} (#{ex.class}) while parsing #{data.length} bytes "+
            "starting '#{data[0..15].inspect}' from #{ip_source}"

          @logger.debug ex.backtrace.join("\n")

        ensure
          @transmission_id_cache[update.transmission_id.to_s] = MauveTime.now

        end

      end

    ensure
      #
      # Thaw the timer 
      #
      Timer.instance.thaw if Timer.instance.frozen?
    end

    def expire_transmission_id_cache
      now = MauveTime.now
      to_delete = []

      @transmission_id_cache.each do |tid, received_at|
        to_delete << tid if (now - received_at) > @transmission_cache_expire_time
      end

      to_delete.each do |tid|
        @transmission_id_cache.delete(tid)
      end
    end

  end   
end

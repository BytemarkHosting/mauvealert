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

      @transmission_id_cache = @transmission_id_cache.delete_if do |cache_data|
        tid, received_at = cache_data
        (now - received_at) > @transmission_cache_expire_time
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
      do_processor
    end
    
    # This processes an incoming packet.  It is in a seperate method so it can
    # be (de)coupled as needed from the UDP server.
    #
    def process_packet(data, client, received_at)
      #
      # Uh-oh.  Nil data?  That's craaaazy
      #
      return nil if data.nil?

      ip_source = "#{client[3]}"
      update = Proto::AlertUpdate.new

      update.parse_from_string(data)

      if @transmission_id_cache[update.transmission_id.to_s]
        logger.debug("Ignoring duplicate transmission id #{update.transmission_id}")
        return nil
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


    private

    def main_loop
      do_processor
      do_timer unless timer_should_stop?
    end

    def do_timer
      #
      # Get the next alert.
      #
      next_alert = Alert.find_next_with_event

      #
      # If we didn't find an alert, or the alert we found is due in the future,
      # look for the next alert_changed object.
      #
      if next_alert.nil? or next_alert.due_at > Time.now
        next_alert_changed = AlertChanged.find_next_with_event
      end

      if next_alert_changed.nil? and next_alert.nil?
        next_to_notify = nil

      elsif next_alert.nil? or next_alert_changed.nil?
        next_to_notify = (next_alert || next_alert_changed)

      else
        next_to_notify = ( next_alert.due_at < next_alert_changed.due_at ? next_alert : next_alert_changed )

      end

      #
      # Nothing to notify?
      #
      if next_to_notify.nil? 
        #
        # Sleep indefinitely
        #
        logger.info("Nothing to notify about -- snoozing for a while.")
        sleep_loops = 600
      else
        #
        # La la la nothing to do.
        #
        logger.info("Next to notify: #{next_to_notify} #{next_to_notify.is_a?(AlertChanged) ? "(reminder)" : "(heartbeat)"} -- snoozing until #{next_to_notify.due_at.iso8601}")
        sleep_loops = ((next_to_notify.due_at - Time.now).to_f / 0.1).round.to_i
      end

      sleep_loops = 0 if sleep_loops.nil? or sleep_loops < 1

      #
      # Ah-ha! Sleep with a break clause.
      #
      sleep_loops.times do
        #
        # Start again if the situation has changed.
        #
        break if timer_should_stop?

        #
        # This is a rate-limiting step for alerts.
        #
        Kernel.sleep 0.1
      end

      return if timer_should_stop? or next_to_notify.nil?

      next_to_notify.poll
    end

    # This is processor loop 
    #
    def do_processor 
      
      sz = Server.packet_buffer_size

      sz.times do
        process_packet(*Server.packet_pop)
      end

      #
      # Now expire the cache.  This will only get processed at most once every minute.
      #
      expire_transmission_id_cache
    end

    def timer_should_stop?
      (Server.packet_buffer_size > 0) or self.should_stop?
    end

  end   

end


require 'mauve/mauve_thread'
require 'mauve/notifiers'
require 'mauve/notifiers/xmpp'

module Mauve

  class Notifier < MauveThread

    DEFAULT_XMPP_MESSAGE = "Mauve server started."
    
    include Singleton

    attr_accessor :buffer, :sleep_interval

    def initialize
      @buffer = Queue.new
    end

    def main_loop

      # 
      # Cycle through the buffer.
      #
      sz = @buffer.size
  
      logger.debug("Notifier buffer is #{sz} in length") if sz > 1 

      (sz > 10 ? 10 : sz).times do
        person, level, alert = @buffer.pop
        begin
          person.do_send_alert(level, alert) 
        rescue StandardError => ex
          logger.debug ex.to_s
          logger.debug ex.backtrace.join("\n")
        end
      end

    end

    def start
      super

      if Configuration.current.notification_methods['xmpp']
        #
        # Connect to XMPP server
        #
        xmpp = Configuration.current.notification_methods['xmpp']
        xmpp.connect 

        Configuration.current.people.each do |username, person|
          # 
          # Ignore people without XMPP stanzas.
          #
          next unless person.xmpp

          #
          # For each JID, either ensure they're on our roster, or that we're in
          # that chat room.
          #
          jid = if xmpp.is_muc?(person.xmpp)
            xmpp.join_muc(person.xmpp) 
          else
            xmpp.ensure_roster_and_subscription!(person.xmpp)
          end

          Configuration.current.people[username].xmpp = jid unless jid.nil?
        end
      end
    end

    def stop
      if Configuration.current.notification_methods['xmpp']
        Configuration.current.notification_methods['xmpp'].close
      end

      super
    end

    class << self

      def enq(a)
        instance.buffer.enq(a)
      end

      alias push enq

    end

  end

end



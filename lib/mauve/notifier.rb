require 'mauve/mauve_thread'
require 'mauve/notifiers'
require 'mauve/notifiers/xmpp'

module Mauve

  class Notifier < MauveThread
    
    include Singleton

    def main_loop
      # 
      # Cycle through the buffer.
      #
      sz = Server.notification_buffer_size

      # Thread.current[:notification_threads] ||= []
      logger.info "Sending #{sz} alerts" if sz > 0
  
      sz.times do
        person, *args = Server.notification_pop
        
        #
        # Nil person.. that's craaazy too!
        #
        next if person.nil?

        person.send_alert(*args) 
      end
    end

    def start
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

      super
    end

    def stop
      super

      #
      # Flush the queue.
      #
      main_loop

      if Configuration.current.notification_methods['xmpp']
        Configuration.current.notification_methods['xmpp'].close
      end

    end

  end

end



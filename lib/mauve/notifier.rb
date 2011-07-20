require 'mauve/mauve_thread'
require 'mauve/notifiers'
require 'mauve/notifiers/xmpp'

module Mauve

  class Notifier < MauveThread
    
    include Singleton

    attr_accessor :sleep_interval

    def main_loop
      # 
      # Cycle through the buffer.
      #
      sz = Server.notification_buffer_size

      return if sz == 0
 
      my_threads = []
      sz.times do
        person, *args = Server.notification_pop
        
        #
        # Nil person.. that's craaazy too!
        #
        break if person.nil?
        my_threads << Thread.new {
          person.do_send_alert(*args) 
        }
      end

      my_threads.each do |t|
        begin
          t.join
        rescue StandardError => ex
          logger.error ex.to_s
          logger.debug ex.backtrace.join("\n")
        end
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
      if Configuration.current.notification_methods['xmpp']
        Configuration.current.notification_methods['xmpp'].close
      end

    end

  end

end



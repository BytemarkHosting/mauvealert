# encoding: utf-8

# Ruby.
require 'pp'
require 'log4r'
require 'monitor'

# Java.  Note that paths are mangeled in jmauve_starter.
require 'java'
require 'smack.jar'
require 'smackx.jar'
include_class "org.jivesoftware.smack.XMPPConnection"
include_class "org.jivesoftware.smackx.muc.MultiUserChat"
include_class "org.jivesoftware.smack.RosterListener"

module Mauve

  module Notifiers    

    module Xmpp
      
      class XMPPSmackException < StandardError
      end

      ## Main wrapper to smack java library.
      #
      # @author Yann Golanski
      # @see http://www.igniterealtime.org/builds/smack/docs/3.1.0/javadoc/
      #
      # This is a singleton which is not idea but works well for mauve's 
      # configuration file set up. 
      #
      # In general, this class is meant to be intialized then the method 
      # create_slave_thread must be called.  The latter will spawn a new 
      # thread that will do the connecting and sending of messages to 
      # the XMPP server.  Once this is done, messages can be send via the 
      # send_msg() method.  Those will be queued and depending on the load,
      # should be send quickly enough.  This is done so that the main thread
      # can not worry about sending messages and can do important work. 
      #
      # @example
      #  bot = Mauve::Notifiers::Xmpp::XMPPSmack.new()
      #  bot.run_slave_thread("chat.bytemark.co.uk", 'mauvealert', 'TopSecret')
      #  msg = "What fresh hell is this? -- Dorothy Parker."
      #  bot.send_msg("yann@chat.bytemark.co.uk", msg)
      #  bot.send_msg("muc:test@conference.chat.bytemark.co.uk", msg)
      #
      # @FIXME  This won't quiet work with how mauve is set up. 
      #
      class XMPPSmack
        
        # Globals are evil.
        @@instance = nil

        # Default constructor.
        #
        # A queue (@queue) is used to pass information between master/slave.
        def initialize ()
          extend(MonitorMixin)
          @logger =  Log4r::Logger.new "mauve::XMPP_smack<#{Process.pid}>"
          @queue = Queue.new 
          @xmpp = nil
          @name = "mauve alert"
          @slave_thread = nil
          @regexp_muc = Regexp.compile(/^muc\:/)
          @regexp_tail = Regexp.compile(/\/.*$/)
          @jid_created_chat = Hash.new()
          @separator = '<->'
          @logger.info("Created XMPPSmack singleton")
        end

        # Returns the instance of the XMPPSmack singleton.
        #
        # @param [String] login The JID as a full address.
        # @param [String] pwd The password corresponding to the JID.
        # @return [XMPPSmack] The singleton instance.
        def self.instance (login, pwd)
          if true == @@instance.nil?
            @@instance = XMPPSmack.new
            jid, tmp = login.split(/@/)
            srv, name = tmp.split(/\//)
            name = "Mauve Alert Bot" if true == name.nil?
            @@instance.run_slave_thread(srv, jid, pwd, name)
            sleep 5 # FIXME: This really should be synced... But how?
          end
          return @@instance
        end

        # Create the thread that sends messages to the server.
        #
        # @param [String] srv The server address.
        # @param [String] jid The JID.
        # @param [String] pwd The password corresponding to the JID.
        # @param [String] name The bot name.
        # @return [NULL] nada
        def run_slave_thread (srv, jid, pwd, name)
          @srv = srv
          @jid = jid
          @pwd = pwd
          @name = name
          @logger.info("Creating slave thread on #{@jid}@#{@srv}/#{@name}.")
          @slave_thread = Thread.new do 
            self.create_slave_thread()
          end
          return nil
        end

        # Returns whether instance is connected and authenticated.
        #
        # @return [Boolean] True or false.
        def is_connected_and_authenticated? ()
          return false if true == @xmpp.nil?
          return (@xmpp.isConnected() and @xmpp.isAuthenticated())
        end

        # Creates the thread that does the actual sending to XMPP.
        # @return [NULL] nada
        def create_slave_thread ()
          begin
            @logger.info("Slave thread is now alive.")
            self.open()
            loop do
              rcp, msg = @queue.deq().split(@separator, 2)
              @logger.debug("New message for '#{rcp}' saying '#{msg}'.")
              if rcp.match(@regexp_muc)
                room = rcp.gsub(@regexp_muc, '').gsub(@regexp_tail, '')
                self.send_to_muc(room, msg)
              else
                self.send_to_jid(rcp, msg)
              end
            end
          rescue XMPPSmackException
            @logger.fatal("Something is wrong")
          ensure 
            @logger.info("XMPP bot disconnect.")
            @xmpp.disconnect()
          end
          return nil
        end

        # Send a message to the recipient.
        #
        # @param [String] rcp The recipent MUC or JID.
        # @param [String] msg The message.
        # @return [NULL] nada
        def send_msg(rcp, msg)
          #if @slave_thread.nil? or not self.is_connected_and_authenticated?()
          #  str = "There is either no slave thread running or a disconnect..."
          #  @logger.warn(str)
          #  self.reconnect()
          #end
          @queue.enq(rcp + @separator + msg)
          return nil
        end

        # Sends a message to a room.
        #
        # @param [String] room The name of the room.
        # @param [String] mgs The message to send.
        # @return [NULL] nada
        def send_to_muc (room, msg)
          if not @jid_created_chat.has_key?(room)
            @jid_created_chat[room] = MultiUserChat.new(@xmpp, room)
            @jid_created_chat[room].join(@name)
          end
          @logger.debug("Sending to MUC '#{room}' message '#{msg}'.")
          @jid_created_chat[room].sendMessage(msg)
          return nil
        end

        # Sends a message to a jid.
        #
        # Do not destroy the chat, we can reuse it when the user log back in again. 
        # Maybe?
        #
        # @param [String] jid The JID of the recipient.
        # @param [String] mgs The message to send.
        # @return [NULL] nada
        def send_to_jid (jid, msg)
          if true == jid_is_available?(jid)
            if not @jid_created_chat.has_key?(jid)
              @jid_created_chat[jid] = @xmpp.getChatManager.createChat(jid, nil)
            end
            @logger.debug("Sending to JID '#{jid}' message '#{msg}'.")
            @jid_created_chat[jid].sendMessage(msg)
          end
          return nil
        end

        # Check to see if the jid is available or not.
        #
        # @param [String] jid The JID of the recipient.
        # @return [Boolean] Whether we can send a message or not.
        def jid_is_available?(jid)
          if true == @xmpp.getRoster().getPresence(jid).isAvailable()
            @logger.debug("#{jid} is available. Status is " +
                          "#{@xmpp.getRoster().getPresence(jid).getStatus()}")
            return true
          else
            @logger.warn("#{jid} is not available. Status is " +
                         "#{@xmpp.getRoster().getPresence(jid).getStatus()}")
            return false
          end
        end

        # Opens a connection to the xmpp server at given port.
        #
        # @return [NULL] nada
        def open()
          @logger.info("XMPP bot is being created.")
          self.open_connection()
          self.open_authentication()
          self.create_roster()
          sleep 5
          return nil
        end

        # Connect to server.
        #
        # @return [NULL] nada
        def open_connection()
          @xmpp = XMPPConnection.new(@srv)
          if false == self.connect()
            str = "Connection refused"
            @logger.error(str)
            raise XMPPSmackException.new(str)
          end
          @logger.debug("XMPP bot connected successfully.")
          return nil
        end

        # Authenticat connection.
        #
        # @return [NULL] nada
        def open_authentication()
          if false == self.login(@jid, @pwd)
            str = "Authentication failed"
            @logger.error(str)
            raise XMPPSmackException.new(str)
          end
          @logger.debug("XMPP bot authenticated successfully.")
          return nil
        end

        # Create a new roster and listener.
        #
        # @return [NULL] nada
        def create_roster
          @xmpp.getRoster().addRosterListener(RosterListener.new())
          @xmpp.getRoster().reload()
          @xmpp.getRoster().getPresence(@xmpp.getUser).setStatus(
            "Purple alert! Purple alert!")
          @logger.debug("XMPP bot roster aquired successfully.")
          return nil
        end

        # Connects to the server.
        #
        # @return [Boolean] true (aka sucess) or false (aka failure).
        def connect ()
          @xmpp.connect()
          return @xmpp.isConnected()
        end
        
        # Login onto the server.
        #
        # @param [String] jid The JID.
        # @param [String] pwd The password corresponding to the JID.
        # @return [Boolean] true (aka sucess) or false (aka failure).
        def login (jid, pwd)
          @xmpp.login(jid, pwd, @name)
          return @xmpp.isAuthenticated()
        end

        # Reconnects in case of errors.
        #
        # @return [NULL] nada
        def reconnect()
          @xmpp.disconnect
          @slave_thread = Thread.new do 
            self.create_slave_thread()
          end
          return nil
        end

        def presenceChanged ()
        end

      end # XMPPSmack


      ## This is the class that gets called in person.rb. 
      #
      # This class is a wrapper to XMPPSmack which does the hard work. It is
      # done this way to conform to the mauve configuration file way of 
      # defining notifications.
      #
      # @author Yann Golanski
      class Default

        # Name of the class.
        attr_reader :name

        # Atrtribute.
        attr_accessor :jid

        # Atrtribute.
        attr_accessor :password

        # Atrtribute.
        attr_accessor :initial_jid

        # Atrtribute.
        attr_accessor :initial_messages
        
        # Default constructor.
        #
        # @param [String] name The name of the notifier.
        def initialize (name)
          extend(MonitorMixin)
          @name = name
          @logger = Log4r::Logger.new "mauve::XMPP_default<#{Process.pid}>"
        end

        # Sends a message to the relevant jid or muc.
        #
        # We have no way to know if a messages was recieved, only that 
        # we send it.
        # 
        # @param [String] destionation
        # @param [Alert] alert A mauve alert class
        # @param [Array] all_alerts subset of current alerts
        # @param [Hash] conditions Supported conditions, see above.
        # @return [Boolean] Whether a message can be send or not. 
        def send_alert(destination, alert, all_alerts, conditions = nil)
          synchronize { 
            client = XMPPSmack.instance(@jid, @password) 
            if not destination.match(/^muc:/)
              if false == client.jid_is_available?(destination.gsub(/^muc:/, ''))
                return false
              end
            end
            client.send_msg(destination, convert_alert_to_message(alert))
            return true
          }
        end

        # Takes an alert and converts it into a message.
        #
        # @param [Alert] alert The alert to convert.
        # @return [String] The message, either as HTML.
        def convert_alert_to_message(alert)
          arr = alert.summary_three_lines
          str = arr[0] + ": " + arr[1]
          str += " -- " + arr[2] if false == arr[2].nil?
          str += "."
          return str
          #return alert.summary_two_lines.join(" -- ")
          #return "<p>" + alert.summary_two_lines.join("<br />") + "</p>"
        end

        # This is so unit tests can run fine.
        include Debug

      end # Default

    end
  end
end

# This is a simple example of usage.  Run with:
#   ../../../jmauve_starter.rb xmpp-smack.rb 
# Clearly, the mauve jabber password is not correct.  
#
#   /!\ WARNING:   DO NOT COMMIT THE REAL PASSWORD TO MERCURIAL!!!
#
def send_msg()
  bot = Mauve::Notifiers::Xmpp::XMPPSmack.instance(
    "mauvealert@chat.bytemark.co.uk/testing1234", '')
  msg = "What fresh hell is this? -- Dorothy Parker."
  bot.send_msg("yann@chat.bytemark.co.uk", msg)
  bot.send_msg("muc:test@conference.chat.bytemark.co.uk", msg)
  sleep 2
end

if __FILE__ == './'+$0
  Thread.abort_on_exception = true
  logger = Log4r::Logger.new('mauve')
  logger.level = Log4r::DEBUG
  logger.add Log4r::Outputter.stdout
  send_msg()
  send_msg()
  logger.info("START")
  logger.info("END")
end

require 'thin'
require 'mauve/mauve_thread'
require 'digest/sha1'

module Mauve
  # 
  # The POP3 server, where messages can also be read.
  #
  class Pop3Server < MauveThread

    include Singleton

    attr_reader :port, :ip

    # Initialize the server
    #
    # Default port is 1110
    # Default IP is 0.0.0.0
    #
    def initialize
      super
      self.port = 1110
      self.ip = "0.0.0.0"
    end
   
    #
    # Set the port
    #
    # @param [Integer] pr
    # @raise [ArgumentError] if the port is not sane
    # ~
    def port=(pr)
      raise ArgumentError, "port must be an integer between 0 and #{2**16-1}" unless pr.is_a?(Integer) and pr < 2**16 and pr > 0
      @port = pr
    end
    
    #
    # Set the IP address.  Unfortunately IPv6 is not OK.
    #
    # @param [String] i The IP address required.
    #
    def ip=(i)
      raise ArgumentError, "ip must be a string" unless i.is_a?(String)
      #
      # Use ipaddr to sanitize our IP.
      #
      IPAddr.new(i)

      @ip = i
    end
    
    # @return [Log4r::Logger]
    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s)
    end

    #
    # This stops the server
    #
    def stop
      if @server.running?
        @server.stop
      else
        @server.stop!
      end

      super
    end

    #
    # This stops the server faster than stop
    #
    def join
      @server.stop! if @server

      super
    end

    private

    #
    # This tarts the server, and keeps it going.
    #
    def main_loop
      unless @server and @server.running?
        @server = Mauve::Pop3Backend.new(@ip.to_s, @port)
        logger.info "Listening on #{@server.to_s}"
        #
        # The next statment doesn't return.
        #
        @server.start
      end
    end

  end    

  #
  # This is the Pop3 Server itself.  It is based on the Thin HTTP server, and hence EventMachine.
  #
  class Pop3Backend < Thin::Backends::TcpServer

    #
    # @return [Log4r::Logger]
    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s)
    end
        
    # Initialize a new connection to the server
    def connect
      @signature = EventMachine.start_server(@host, @port, Pop3Connection)
    end
        
    # Disconnect the server, but only if EventMachine is still going.
    def disconnect
      #
      # Only do this if EventMachine is still going.. The http_server may have
      # stopped it already.
      #
      EventMachine.stop_server(@signature) if EventMachine.reactor_running?
    end

  end

  #
  # This class represents and individual connection, and understands some POP3
  # commands.
  #
  class Pop3Connection < EventMachine::Connection

    # The username
    attr_reader :user

    # Default CR+LF combo.
    CRLF = "\r\n"

    # @return [Log4r::Logger]
    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s)
    end

    # This is called once the connection has been established.  It says hello
    # to the client, and resets the state.
    def post_init
      logger.info "New connection"
      send_data "+OK #{self.class.to_s} started"
      @state = :authorization
      @user  = nil
      @messages = []
      @level    = nil
    end

    # This returns a list of commands allowed in a state.
    #
    # @param [Symbol] The state to query, defaults to the current state.
    # @return [Array] An array of permitted comands.
    #
    def permitted_commands(state=@state)
     case @state
        when :authorization
          %w(QUIT USER PASS CAPA)
        when :transaction
          %w(QUIT STAT LIST RETR DELE NOOP RSET UIDL CAPA)
        when :update
          %w(QUIT)
      end
    end

    # This returns a list of capabilities in a given state.
    #
    # @param [Symbol] The state to query, defaults to the current state.
    # @return [Array] An array of capabilities.
    def capabilities(state=@state)
     case @state
        when :transaction
          %w(CAPA UIDL)
        when :authorization
          %w(CAPA UIDL USER) 
        else
          []
      end
    end

    # This method handles a command, and parses it.
    #
    # The following POP3 commands are understood:
    #   QUIT
    #   USER
    #   PASS
    #   STAT
    #   LIST
    #   RETR
    #   DELE
    #   NOOP
    #   RSET
    #   CAPA
    #   UIDL
    #
    # The command is checked against a list of permitted commands, given the
    # state of the connection, and returns an error if the command is
    # forbidden.
    #
    # @param [String] data The data to process.
    #
    def receive_data (data)
      data.split(CRLF).each do |cmd|
        break if error?

        if cmd =~ Regexp.new('\A('+self.permitted_commands.join("|")+')\b')
          case $1
            when "QUIT"
              do_process_quit cmd
            when "USER"
              do_process_user cmd
            when "PASS"
              do_process_pass cmd
            when "STAT"
              do_process_stat cmd
            when "LIST"
              do_process_list cmd
            when "RETR"
              do_process_retr cmd
            when "DELE"
              do_process_dele cmd
            when "NOOP"
              do_process_noop cmd
            when "RSET"
              do_process_rset cmd
            when "CAPA"
              do_process_capa cmd
            when "UIDL"
              do_process_uidl cmd
            else
              do_process_error cmd
          end
        else
          do_process_error cmd
        end
      end
    end
 
    # This sends the data back to the user.  A CR+LF is joined to the end of
    # the data.
    #
    # @param [String] d The data to send back.
    def send_data(d)
      d += CRLF
      super unless error?
    end

    private

    # This deals with CAPA, returning a string of capabilities in the current
    # connection state.
    #
    # @param [String] a The complete CAPA command sent by the client.
    #
    def do_process_capa(a)
      send_data (["+OK Capabilities follow:"] + self.capabilities + ["."]).join(CRLF)
    end

    # This deals with the USER command.
    #
    # Any of low, normal, urgent can be appended to the username, to select
    # only alarms of that level to be shown.
    #
    # e.g.
    #   patrick+low
    #
    # will show only alerts of a LOW level.
    #
    # @param [String] s The complete USER command sent by the client.
    #
    def do_process_user(s)
      allowed_levels = Mauve::AlertGroup::LEVELS.collect{|l| l.to_s}

      if s =~ /\AUSER +(\w+)\+(#{allowed_levels.join("|")})/
        # Allow alerts to be shown by level.
        #
        @user  = $1
        @level = $2
        #
        send_data "+OK Only going to show #{@level} alerts."

     elsif s =~ /\AUSER +([\w]+)/
        @user =  $1

        send_data "+OK"
      else
        send_data "-ERR Username not understood."
      end
    end

    # This processes the PASS command.  It uses the Mauve::Authenticate class
    # to authenticate the user.  Once authenticated, the state is set to :transaction.
    #
    # @param [String] s The complete PASS command sent by the client.
    def do_process_pass(s)
      
      if @user and s =~ /\APASS +(\S+)/
        if Mauve::Authentication.authenticate(@user, $1)
          @state = :transaction
          send_data "+OK Welcome #{@user} (#{@level})." 
        else
          send_data "-ERR Authentication failed."
        end        
      else
        send_data "-ERR USER comes first."
      end
    end

    #
    # This just sends an "ERR Unknown command" string back to the user.
    #
    # @param [String] a The complete command from the client that caused this error.
    def do_process_error(a)
      send_data "-ERR Unknown comand."
    end

    # This does a NOOP.
    #
    # @param [String] a The complete NOOP command from the client.
    def do_process_noop(a)
      send_data "+OK Thanks."
    end

    # Delete is processed as a NOOP
    alias do_process_dele do_process_noop

    # This logs a user out, and closes the connection.  The state is set to :update.
    #
    # @param [String] a The complete QUIT command from the client.
    def do_process_quit(a)
      @state = :update

      send_data "+OK bye."

      close_connection_after_writing
    end

    # This sends the number of messages, and their size back to the client.
    #
    # @param [String] a The complete STAT command from the client.
    def do_process_stat(a)
      send_data "+OK #{self.messages.length} #{self.messages.inject(0){|s,m| s+= m[1].length}}"
    end

    # This sends a list of the messages back to the client.
    #
    # @param [String] a The complete LIST command from the client.
    #
    def do_process_list(a)
      d = []
      if a =~ /\ALIST +(\d+)\b/
        ind = $1.to_i
        if ind > 0 and ind <= self.messages.length
          d << "+OK #{ind} #{self.messages[ind-1][1].length}"
        else
          d << "-ERR Unknown message."
        end
      else
        d << "+OK #{self.messages.length} messages (#{self.messages.inject(0){|s,m| s+= m[1].length}} octets)."
        self.messages.each_with_index{|m,i| d << "#{i+1} #{m[1].length}"}
        d << "."
      end

      send_data d.join(CRLF)
    end

    # This sends the UID of a message back to the client.
    #
    # @param [String] a The complete UIDL command from the client.
    def do_process_uidl(a)
      if a =~ /\AUIDL +(\d+)\b/
        ind = $1.to_i
        if ind > 0 and ind <= self.messages.length
          m = self.messages[ind-1][0].id
          send_data "+OK #{ind} #{m}"
        else
          send_data "-ERR Message not found."
        end
      else
        d = ["+OK "]
        self.messages.each_with_index{|m,i| d << "#{i+1} #{m[0].id}"}
        d << "."

        send_data d.join(CRLF)
      end
    end

    # This retrieves a message for the client.
    #
    # @param [String] a The complete RETR command from the client.
    #
    def do_process_retr(a)
      if a =~ /\ARETR +(\d+)\b/
        ind = $1.to_i
        if ind > 0 and ind <= self.messages.length
          alert_changed, msg = self.messages[ind-1]
          send_data ["+OK #{msg.length} octets", msg, "."].join(CRLF)
          note =  "#{alert_changed.update_type.capitalize} notification downloaded via POP3 by #{@user}" 
          logger.info note+" about #{alert_changed}."
          h = History.new(:alerts => [alert_changed.alert_id], :type => "notification", :event => note, :user => @user)
          logger.error "Unable to save history due to #{h.errors.inspect}" if !h.save
        else
          send_data "-ERR Message not found."
        end
      else
        send_data "-ERR Boo."
      end

    end

    protected

    #
    # These are the messages in the mailbox.  It looks for the first 100 alert_changed, and formats them into emails, and returns an array of
    #
    #  [alert_changed, email]
    #
    # @return [Array] Array of alert_changeds and emails.
    #
    def messages
      if @messages.empty?
        @messages = []

        email = Configuration.current.notification_methods['email']

        alerts_seen = []

        #
        # A maximum of the 100 most recent alerts.
        #
        AlertChanged.first(100, :person => self.user, :was_relevant => true).each do |a|
          #
          # Not interested in alerts 
          #
          next unless @level.nil? or a.level.to_s == @level

          #
          # Only interested in alerts
          #
          next unless a.alert.is_a?(Mauve::Alert)

          #
          # Only one message per alert.
          #
          next if alerts_seen.include?([a.alert_id, a.update_type])

          relevant = case a.update_type
            when "raised"
              a.alert.raised?
            when "acknowledged"
              a.alert.acknowledged?
            when "cleared"
              a.alert.cleared?
            else
              false
          end

          next unless relevant

          alerts_seen << [a.alert_id, a.update_type]

          @messages << [a, email.prepare_message(self.user+"@"+Server.instance.hostname, a.alert, [])]
        end
      end
      
      @messages
    end

  end

end


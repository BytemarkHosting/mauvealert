require 'thin'
require 'mauve/mauve_thread'
require 'digest/sha1'

module Mauve
  # 
  # API to control the web server
  #
  class Pop3Server < MauveThread

    include Singleton

    attr_reader :port, :ip
    
    def initialize
      super
      self.port = 1110
      self.ip = "0.0.0.0"
    end
   
    def port=(pr)
      raise ArgumentError, "port must be an integer between 0 and #{2**16-1}" unless pr.is_a?(Integer) and pr < 2**16 and pr > 0
      @port = pr
    end
    
    def ip=(i)
      raise ArgumentError, "ip must be a string" unless i.is_a?(String)
      #
      # Use ipaddr to sanitize our IP.
      #
      @ip = IPAddr.new(i)
    end

    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s)
    end

    def main_loop
      unless @server and @server.running?
        @server = Mauve::Pop3Backend.new(@ip.to_s, @port)
        logger.info "Listening on #{@server.to_s}"
        @server.start
      end
    end

    def stop
      @server.stop if @server and @server.running?
      super
    end

    def join
      @server.stop! if @server and @server.running?
      super
    end

  end    

  class Pop3Backend < Thin::Backends::TcpServer

    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s)
    end
        
    # Connect the server
    def connect
      @signature = EventMachine.start_server(@host, @port, Pop3Connection)
    end
        
  end


  class Pop3Connection < EventMachine::Connection

    attr_reader :user

    CRLF = "\r\n"

    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s)
    end

    def post_init
      logger.info "New connection"
      send_data "+OK #{self.class.to_s} started"
      @state = :authorization
      @user  = nil
      @messages = []
      @level    = nil
    end

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

    def receive_data (data)
      data.split(CRLF).each do |d|
        break if error?

        if d =~ Regexp.new('\A('+self.permitted_commands.join("|")+')\b')
          case $1
            when "QUIT"
              do_process_quit data
            when "USER"
              do_process_user data
            when "PASS"
              do_process_pass data
            when "STAT"
              do_process_stat data
            when "LIST"
              do_process_list data
            when "RETR"
              do_process_retr data
            when "DELE"
              do_process_dele data
            when "NOOP"
              do_process_noop data
            when "RSET"
              do_process_rset data
            when "CAPA"
              do_process_capa data
            when "UIDL"
              do_process_uidl data
            else
              do_process_error data
          end
        else
          do_process_error data
        end
      end
    end
  
    def send_data(d)
      d += CRLF
      super unless error?
    end

    def do_process_capa(a)
      send_data (["+OK Capabilities follow:"] + self.capabilities + ["."]).join(CRLF)
    end

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

    def do_process_error(a)
      send_data "-ERR Unknown comand."
    end

    def do_process_noop(a)
      send_data "+OK Thanks."
    end

    alias do_process_dele do_process_noop

    def do_process_quit(a)
      @state = :update

      send_data "+OK bye."

      close_connection_after_writing
    end

    def do_process_stat(a)
      send_data "+OK #{self.messages.length} #{self.messages.inject(0){|s,m| s+= m[1].length}}"
    end

    def do_process_list(a)
      d = []
      if a =~ /\ALIST +(\d+)\b/
        ind = $1.to_i
        if ind > 0 and ind <= self.messages.length
          d << "+OK #{ind} #{self.messages[ind-1].length}"
        else
          d << "-ERR Unknown message."
        end
      else
        d << "+OK #{self.messages.length} messages (#{self.messages.inject(0){|s,m| s+= m[1].length}} octets)."
        self.messages.each_with_index{|m,i| d << "#{i+1} #{m.length}"}
        d << "."
      end

      send_data d.join(CRLF)
    end

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

    def do_process_retr(a)
      if a =~ /\ARETR +(\d+)\b/
        ind = $1.to_i
        if ind > 0 and ind <= self.messages.length
          alert_changed, msg = self.messages[ind-1]
          send_data ["+OK #{msg.length} octets", msg, "."].join(CRLF)
          note =  "#{alert_changed.update_type.capitalize} notification downloaded via POP3 by #{@user}" 
          logger.info note+" about #{alert_changed}."
          h = History.new(:alert_id => alert_changed.alert_id, :type => "notification", :event => note)
          logger.error "Unable to save history due to #{h.errors.inspect}" if !h.save
        else
          send_data "-ERR Message not found."
        end
      else
        send_data "-ERR Boo."
      end

    end

    #
    # These are the messages in the mailbox.
    #
    def messages
      if @messages.empty?
        @messages = []
        smtp = Mauve::Notifiers::Email::Default.new("TODO: why do I need to put this argument here?")
        alerts_seen = []

        AlertChanged.all(:person => self.user).each do |a|
          #
          # Not interested in alerts 
          #
          next unless @level.nil? or a.level.to_s == @level

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

          @messages << [a, smtp.prepare_message(self.user, a.alert, [])]
        end
      end
      
      @messages
    end

  end

end


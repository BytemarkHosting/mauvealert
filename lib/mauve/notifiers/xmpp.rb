require 'log4r'
require 'xmpp4r'
require 'xmpp4r/roster'
require 'xmpp4r/muc'
# require 'xmpp4r/xhtml'
# require 'xmpp4r/discovery/helper/helper'
require 'mauve/notifiers/debug'



#
# A couple of monkey patches to fix up all this nonsense.
#
module Jabber
  class Stream
    def close
      #
      # Just close
      #
      close!
    end

    def close!
      10.times do
        pr = 0
        @tbcbmutex.synchronize { pr = @processing }
        break if pr = 0
        Thread::pass if pr > 0
        sleep 1
      end

      # Order Matters here! If this method is called from within 
      # @parser_thread then killing @parser_thread first would 
      # mean the other parts of the method fail to execute. 
      # That would be bad. So kill parser_thread last
      @tbcbmutex.synchronize { @processing = 0 }
      if @fd and !@fd.closed?
        @fd.close 
        stop 
      end
      @status = DISCONNECTED
    end
  end
end




module Mauve
  module Notifiers    
    module Xmpp
      
#      class CountingMUCClient < Jabber::MUC::SimpleMUCClient
#
#        attr_reader :participants
#
#        def initialize(*a)
#          super(*a)
#          @participants = 0
#          self.on_join  { @participants += 1 }
#          self.on_leave { @participants -= 1 }
#        end
#
#      end
#      
      class Default

        include Jabber

        # Atrtribute.
        attr_reader :name

        # Atrtribute.
        attr_accessor :password

        def initialize(name)
          Jabber::logger = self.logger       
#         Jabber::debug = true
#          Jabber::warnings = true

          @name = name
          @mucs = {}
          @roster = nil
          @closing = false
          @client = nil
        end

        def logger
          # Give the logger a sane name
          @logger ||= Log4r::Logger.new self.class.to_s.sub(/::Default$/,"")
        end
       
        def jid=(jid)
          @jid = JID.new(jid)
        end
 
        def connect
          logger.debug "Starting connection to #{@jid}"

          # Make sure we're disconnected.
          self.close if @client.is_a?(Client)

          @client = Client.new(@jid) 

          @closing = false
          @client.connect
          @client.auth_nonsasl(@password, false)
          @roster = Roster::Helper.new(@client)

          # Unconditionally accept all roster add requests, and respond with a
          # roster add + subscription request of our own if we're not subscribed
          # already
          @roster.add_subscription_request_callback do |ri, presence|
            Thread.new do
              if is_known_contact?(presence.from)
                logger.info("Accepting subscription request from #{presence.from}")
                @roster.accept_subscription(presence.from)
                ensure_roster_and_subscription!(presence.from)
              else
                logger.info("Declining subscription request from #{presence.from}")
                @roster.decline_subscription(presence.from)
              end
            end.join
          end

          @client.add_message_callback do |m|
            receive_message(m)
          end

          @roster.wait_for_roster

          @client.send(Presence.new(nil, "Woo!").set_type(nil))

          logger.info "Connected as #{@jid}"

          @client.on_exception do |ex, stream, where|
            #
            # The XMPP4R exception clauses in Stream all close the stream, so
            # we just need to reconnect.
            #
            unless ex.nil? or @closing 
              logger.warn(["Caught",ex.class,ex.to_s,"during XMPP",where].join(" "))
              logger.debug ex.backtrace.join("\n")
              @closing = true
              connect
              @mucs.each do |jid, muc|
                @mucs.delete(jid)
                join_muc(muc[:jid], muc[:password])
              end
            end
          end
        end  

        #
        # Kills the processor thread
        #
        def stop
          @client.stop
        end

        def close
          @closing = true
          if @client 
            if  @client.is_connected?
              @mucs.each do |jid, muc|
                muc[:client].exit("Goodbye!") if muc[:client].active?
              end 
              @client.send(Presence.new(nil, "Goodbye!").set_type(:unavailable))
            end
            @client.close!
          end
        end

        def ready?
          @client.is_a?(Jabber::Client) and @client.is_connected?
        end
        
        # 
        # Takes an alert and converts it into a message.
        #
        def convert_alert_to_message(alert)
        end

        # Attempt to send an alert using XMPP. 
        # +destination+ is the JID you're sending the alert to. This should be
        # a bare JID in the case of an individual, or muc:<room>@<server> for 
        # chatrooms (XEP0045). The +alert+ object is turned into a pretty
        # message and sent to the destination as a message, if the +conditions+
        # are met. all_alerts are currently ignored.
        #
        # The only suported condition at the moment is :if_presence => [choices]
        # which checks whether the jid in question has a presence matching one
        # or more of the choices - see +check_jid_has_presence+ for options.

        def send_alert(destination, alert, all_alerts, conditions = {})
          destination_jid = JID.new(destination)         
 
          was_suppressed = conditions[:was_suppressed] || false
          is_suppressed  = conditions[:is_suppressed]  || false
          
          if conditions && !check_alert_conditions(destination_jid, conditions) 
            logger.info("Alert conditions not met, not sending XMPP alert to #{destination_jid}")
            return false
          end
         
          template_file = File.join(File.dirname(__FILE__),"templates","xmpp.txt.erb")

          txt = if File.exists?(template_file) 
            ERB.new(File.read(template_file)).result(binding).chomp
          else
            logger.error("Could not find xmpp.txt.erb template")
            alert.to_s
          end

          template_file = File.join(File.dirname(__FILE__),"templates","xmpp.html.erb")

          xhtml = if File.exists?(template_file)
            ERB.new(File.read(template_file)).result(binding).chomp
          else
            logger.error("Could not find xmpp.txt.erb template")
            alert.to_s
          end

          msg_type = (is_muc?(destination_jid) ? :groupchat : :chat)

          send_message(destination_jid, txt, xhtml, msg_type)
        end

        # Sends a message to the destionation.
        def send_message(jid, msg, html_msg=nil, msg_type=:chat)
          jid = JID.new(jid) unless jid.is_a?(JID)

          message = Message.new(jid)
          message.body = msg
          if html_msg 
            begin
              html_msg = REXML::Document.new(html_msg) unless html_msg.is_a?(REXML::Document)
              message.add_element(html_msg) 
            rescue REXML::ParseException
              logger.error "Bad XHTML: #{html_msg.inspect}"
            end
          end

          message.to   = jid
          message.type = msg_type

          if message.type == :groupchat and is_muc?(jid)
            jid = join_muc(jid.strip)
            muc = @mucs[jid][:client]

            if muc
              muc.send(message)
              true
            else
              logger.warn "Failed to join MUC #{jid} when trying to send a message"
              false
            end
          else
            #
            # We aren't interested in sending things to people who aren't online.
            #
            ensure_roster_and_subscription!(jid)

            if check_jid_has_presence(jid)
              @client.send(message)
              true
            else
              false
            end
          end
        end

        #
        # Joins a chat, and returns the stripped JID of the chat joined.
        #
        def join_muc(jid, password=nil) 
          if jid.is_a?(String) and jid =~ /^muc:(.*)/
            jid = JID.new($1) 
          end
            
          unless jid.is_a?(JID)
            logger.warn "#{jid} is not a MUC"
            return
          end

          jid.resource = @client.jid.resource if jid.resource.to_s.empty?

          if !@mucs[jid.strip]

            logger.debug("Adding new MUC client for #{jid}")
            
            @mucs[jid.strip] = {:jid => jid, :password => password, :client => Jabber::MUC::MUCClient.new(@client)}
            
            # Add some callbacks
            @mucs[jid.strip][:client].add_message_callback do |m|
              receive_message(m)
            end

            @mucs[jid.strip][:client].add_private_message_callback do |m|
              receive_message(m)
            end

          end

          if !@mucs[jid.strip][:client].active?
            #
            # Make sure we have a resource.
            #
            @mucs[jid.strip][:client].join(jid, password)

            logger.info("Joined #{jid.strip}")
          else
            logger.debug("Already joined #{jid.strip}.")
          end

          #
          # Return the JID object
          #
          jid.strip
        end 
        
        # 
        # Checks whether the destination JID is a MUC. 
        #
        def is_muc?(jid)
          (jid.is_a?(JID)    and @mucs.keys.include?(jid.strip)) or
          (jid.is_a?(String) and jid =~ /^muc:(.*)/)

          #
          # It would be nice to use service discovery to determin this, but it
          # turns out that it is shite in xmpp4r.  It doesn't return straight
          # away with an answer, making it a bit useless.  Some sort of weird
          # threading issue, I think.
          #
          # begin
          #   logger.warn caller.join("\n")
          #   cl  = Discovery::Helper.new(@client)
          #   res = cl.get_info_for(jid.strip)
          #   @client.wait
          #   logger.warn "hello #{res.inspect}"
          #   res.is_a?(Discovery::IqQueryDiscoInfo) and res.identity.category == :conference
          # rescue Jabber::ServerError => ex
          #  false
          # end
        end

        # 
        # Checks to see if the JID is in our roster, and whether we are
        # subscribed to it or not. Will add to the roster and subscribe as
        # is necessary to ensure both are true.
        #
        def ensure_roster_and_subscription!(jid)
          return jid if is_muc?(jid)

          jid = JID.new(jid) unless jid.is_a?(JID)

          ri = @roster.find(jid).values.first
          @roster.add(jid, nil, true) if ri.nil? 

          ri = @roster.find(jid).values.first
          ri.subscribe unless [:to, :both, :remove].include?(ri.subscription)
          ri.jid
        rescue StandardError => ex
          logger.error("Problem ensuring that #{jid} is subscribed and in mauve's roster: #{ex.inspect}")
          nil
        end

        protected

        def receive_message(msg)
          #
          # Don't talk to self
          #
          if @jid == msg.from or @mucs.any?{|jid, muc| muc.is_a?(Hash) and muc.has_key?(:client) and muc[:client].jid == msg.from}
            return nil
          end 

          # We only want to hear messages from known contacts.
          unless is_known_contact?(msg.from)
            # ignore message
            logger.info "Ignoring message from unknown contact #{msg.from}"
            return nil
          end

          case msg.type
            when :error
              receive_error_message(msg)
            when :groupchat
              receive_groupchat_message(msg)
            else
              receive_normal_message(msg)
          end
        end

        def receive_error_message(msg)
          logger.warn("Caught XMPP error #{msg}") 
          nil
        end

        def receive_normal_message(msg)
          #
          # Treat invites specially
          #
          if msg.x("jabber:x:conference")
            #
            # recieved an invite.  Need to mangle the jid.
            #
            jid =JID.new(msg.x("jabber:x:conference").attribute("jid"))
            # jid.resource = @client.jid.resource
            logger.info "Received an invite to #{jid}"
            unless join_muc(jid)
              logger.warn "Failed to join MUC #{jid} following invitation"
              return nil
            end            
          elsif msg.body
            #
            # Received a message with a body.
            #
            jid = msg.from
          end

          if jid 
            reply = parse_command(msg)
            send_message(jid, reply, nil, msg.type)
          end
        end

        def receive_groupchat_message(msg)
          #
          # We only want group chat messages from MUCs we're already joined to,
          # that we've not sent ourselves, that are not historical, and that
          # match our resource or node in the body.
          #
          if @mucs[msg.from.strip][:client].is_a?(MUC::MUCClient) and
                msg.x("jabber:x:delay") == nil and 
                (msg.body =~ /\b#{Regexp.escape(@mucs[msg.from.strip][:client].jid.resource)}\b/i or
                msg.body =~ /\b#{Regexp.escape(@client.jid.node)}\b/i)

            receive_normal_message(msg) 
          end
        end

        def parse_command(msg)
          case msg.body
            when /help/i
              do_parse_help(msg)
            when /show\s?/i
              do_parse_show(msg)
            when /ack/i
              do_parse_ack(msg)
            else
              File.executable?('/usr/games/fortune') ? `/usr/games/fortune -s -n 60`.chomp : "Sorry.  I don't understand.  Try asking me for help."
          end          
        end

        def do_parse_help(msg)
          msg.body =~ /help\s+(\w+)/i
          cmd = $1
          
          return case cmd
            when "show"
              <<EOF
Show command: Lists all raised or acknowledged alerts, or the first or last few.
e.g.
  show  -- shows all raised alerts
  show ack -- shows all acknowledged alerts
  show first 10 acknowledged -- shows first 10 acknowledged
  show last 5 raised -- shows last 5 raised alerts 
EOF
            when /^ack/
              <<EOF
Acknowledge command: Acknowledges one or more alerts for a set period of time.  This can only be done from a "private" chat.
e.g.
  ack 1 for 2 hours -- acknowledges alert no. 1 for 2 wall-clock hours
  ack 1,2,3 for 2 working hours -- acknowledges alerts 1, 2, and 3 for 2 working hours
EOF
            else
              "I am Mauve #{Mauve::VERSION}.  I understand \"help\", \"show\" and \"acknowledge\" commands.  Try \"help show\"."
          end       
        end

        def do_parse_show(msg)
          return "Sorry -- I don't understand your show command." unless
             msg.body =~ /show(?:\s+(first|last)\s+(\d+))?(?:\s+(events|raised|ack(?:d|nowledged)?))?/i

          first_or_last = $1
          n_items = ($2 || -1).to_i

          type = $3 || "raised"
          type = "acknowledged" if type =~ /^ack/
          
          msg = []
          
          items = case type
            when "acknowledged"
              Alert.all_acknowledged
            when "events"
              History.all(:created_at.gte => Time.now - 24.hours)
            else 
              Alert.all_raised
          end

          if first_or_last == "first"
            items = items.first(n_items) if n_items >= 0 
          elsif first_or_last == "last"
            items = items.last(n_items) if n_items >= 0 
          end

          return "Nothing to show" if items.length == 0          

          template_file = File.join(File.dirname(__FILE__),"templates","xmpp.txt.erb")
          if File.exists?(template_file)
            template = File.read(template_file)
          else
            logger.error("Could not find xmpp.txt.erb template")
            template = nil
          end 

          (["Alerts #{type}:"] + items.collect do |alert| 
            "#{alert.id}: " + ERB.new(template).result(binding).chomp
          end).join("\n")
        end

        def do_parse_ack(msg)
          return "Sorry -- I don't understand your acknowledge command." unless
             msg.body =~ /ack(?:nowledge)?\s+([\d,]+)\s+for\s+(\d+)\s+(work(?:ing)|day(?:time)|wall(?:-?clock))?\s*hours?(?:\s(.*))?/i
          
          alerts, n_hours, type_hours, note = [$1,$2, $3, $4]

          alerts = alerts.split(",")
          n_hours = n_hours.to_i

          type_hours = case type_hours
            when /^wall/
              "wallclock"
            when /^work/
              "working"
            else
              "daytime"
          end
          
          ack_until = Time.now.in_x_hours(n_hours, type_hours)
          username = get_username_for(msg.from)

          if is_muc?(Configuration.current.people[username].xmpp)
            return "I'm sorry -- if you want to acknowledge alerts, please do it from a private chat"
          end

          msg = []
          msg << "Acknowledgment results:" if alerts.length > 1

          alerts.each do |alert_id|
            alert = Alert.get(alert_id)

            if alert.nil?
              msg << "#{alert_id}: alert not found" 
              next
            end

            if alert.cleared?
              msg << "#{alert_id}: alert already cleared" if alert.cleared?
              next
            end

            if alert.acknowledge!(Configuration.current.people[username], ack_until)
              msg << "#{alert_id}: Acknowledged until #{ack_until.to_s_human}"
            else
              msg << "#{alert_id}: Acknowledgment failed."
            end
          end

          return msg.join("\n")
        end

        def check_alert_conditions(destination, conditions)
          any_failed = conditions.keys.collect do |key|
            case key
              when :if_presence : check_jid_has_presence(destination, conditions[:if_presence])
              else 
                #raise ArgumentError.new("Unknown alert condition, #{key} => #{conditions[key]}")
                # FIXME - clean up this use of :conditions to pass arbitrary
                # parameters to notifiers; for now we need to ignore this. 
                true
            end
          end.include?(false)
          !any_failed
        end
        
        # Checks our roster to see whether the jid has a resource with at least 
        # one of the included presences. Acceptable +presence+ types and their 
        # meanings for individuals:
        #
        #   :online, :offline               - user is logged in or out
        #   :available                      - jabber status is nil (available) or chat
        #   :unavailable -                  - jabber status is away, dnd or xa
        #   :unknown                        - don't know (not in roster)
        #
        # For MUCs: TODO
        # Returns true if at least one of the presence specifiers for the jid
        # is met, false otherwise. Note that if the alerter can't see the alertee's
        # presence, only 'unknown' will match - generally, you'll want [:online, :unknown]
        def check_jid_has_presence(jid, presence_or_presences = [:online, :unknown])
          jid = JID.new(jid) unless jid.is_a?(JID)

          return true if is_muc?(jid)

          reconnect unless @client

          presences = [presence_or_presences].flatten
          roster_item = @roster.find(jid)
          roster_item = roster_item[roster_item.keys[0]]
          resource_presences = []
          roster_item.each_presence {|p| resource_presences << p.show } if roster_item

          results = presences.collect do |need_presence|
            case need_presence
              when :online      : (roster_item && [:to, :both].include?(roster_item.subscription) && roster_item.online?)
              when :offline     : (roster_item && [:to, :both].include?(roster_item.subscription) && !roster_item.online?)
              when :available   : (roster_item && [:to, :both].include?(roster_item.subscription) && (resource_presences.include?(nil) ||
                                                                                                      resource_presences.include?(:chat)))
              # No resources are nil or chat
              when :unavailable : (roster_item && [:to, :both].include?(roster_item.subscription) && (resource_presences - [:away, :dnd, :xa]).empty?)
              # Not in roster or don't know subscription
              when :unknown     : (roster_item.nil? || [:none, :from].include?(roster_item.subscription)) 
            else
              raise ArgumentError.new("Unknown presence possibility: #{need_presence}")
            end
          end
          results.include?(true)
        end

        #
        # Returns the username of the jid, if any
        #
        def get_username_for(jid)
          jid = JID.new(jid) unless jid.is_a?(JID)
       
          #
          # Resolve MUC JIDs.
          #
          if is_muc?(jid)
            muc_jid = get_jid_from_muc_jid(jid)
            jid = muc_jid unless muc_jid.nil?
          end
 
          ans = Configuration.current.people.find do |username, person|
            next unless person.xmpp.is_a?(JID)
            person.xmpp.strip == jid.strip
          end

          ans.nil? ? ans : ans.first
        end

        #
        # Tries to establish a real JID from a MUC JID.
        #
        def get_jid_from_muc_jid(jid)
          #
          # Resolve the JID for MUCs.
          #
          jid = JID.new(jid) unless jid.is_a?(JID)
          return nil unless @mucs.has_key?(jid.strip)
          return nil unless @mucs[jid.strip].has_key?(:client)
          return nil unless @mucs[jid.strip][:client].active?

          roster = @mucs[jid.strip][:client].roster[jid.resource]
          return nil unless roster

          x = roster.x('http://jabber.org/protocol/muc#user')
          return nil unless x

          items = x.items
          return nil if items.nil? or items.empty?

          jids = items.collect{|item| item.jid}
          return nil if jids.empty?

          jids.first
        end

        def is_known_contact?(jid)
          !get_username_for(jid).nil?
        end
        
      end
    end
  end
end


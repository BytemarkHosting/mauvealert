require 'log4r'
require 'xmpp4r'
require 'xmpp4r/xhtml'
require 'xmpp4r/roster'
require 'xmpp4r/muc/helper/simplemucclient'
require 'mauve/notifiers/debug'
#Jabber::debug = true

module Mauve
  module Notifiers    
    module Xmpp
      
      class CountingMUCClient < Jabber::MUC::SimpleMUCClient

        attr_reader :participants

        def initialize(*a)
          super(*a)
          @participants = 0
          self.on_join  { @participants += 1 }
          self.on_leave { @participants -= 1 }
        end

      end
      
      class Default

        include Jabber
        
        # Atrtribute.
        attr_reader :name

        # Atrtribute.
        attr_accessor :jid, :password

        # Atrtribute.
        attr_accessor :initial_jid

        # Atrtribute.
        attr_accessor :initial_messages
        
        def initialize(name)
          @name = name
          @mucs = {}
          @roster = nil
        end

        def logger
          @logger ||= Log4r::Logger.new self.class.to_s
        end

        def reconnect
          if @client
            begin
              logger.debug "Jabber closing old client connection"
              @client.close
              @client = nil
              @roster = nil
            rescue Exception => ex
              logger.error "#{ex} when reconnecting"
            end
          end

          logger.debug "Jabber starting connection to #{@jid}"
          @client = Client.new(JID::new(@jid))
          @client.connect
          logger.debug "Jabber authentication"

          @client.auth_nonsasl(@password, false)
          @roster = Roster::Helper.new(@client)

          # Unconditionally accept all roster add requests, and respond with a
          # roster add + subscription request of our own if we're not subscribed
          # already
          @roster.add_subscription_request_callback do |ri, stanza|
            Thread.new do
              logger.debug("Accepting subscription request from #{stanza.from}")
              @roster.accept_subscription(stanza.from)
              ensure_roster_and_subscription!(stanza.from)
            end.join
          end

          @roster.wait_for_roster
          logger.debug "Jabber authenticated, setting presence"

          @client.send(Presence.new.set_type(:available))
          @mucs = {}
          
          logger.debug "Jabber is ready in theory"
        end  

        def reconnect_and_retry_on_error
          @already_reconnected = false
          begin
            yield
          rescue StandardError => ex
            logger.error "#{ex} during notification\n"
            logger.debug ex.backtrace
            if !@already_reconnected
              reconnect
              @already_reconnected = true
              retry
            else
              raise ex
            end
          end
        end  

        def connect
          self.reconnect_and_retry_on_error { self.send_msg(@initial_jid, "Hello!") }
        end

        def close
          self.send_msg(@initial_jid, "Goodbye!")
          @client.close
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

        def send_alert(destination, alert, all_alerts, conditions = nil)
          #message = Message.new(nil, alert.summary_two_lines.join("\n"))
          message = Message.new(nil, convert_alert_to_message(alert))
          
          if conditions
            @suppressed_changed = conditions[:suppressed_changed]
          end
          
          # MUC JIDs are prefixed with muc: - we need to strip this out.
          destination_is_muc, dest_jid = self.is_muc?(destination)

          begin
            xhtml = XHTML::HTML.new("<p>" +
                                    convert_alert_to_message(alert)+
#                                    alert.summary_three_lines.join("<br />") +
                                    #alert.summary_two_lines.join("<br />") +
                                    "</p>") 
            message.add_element(xhtml)
          rescue REXML::ParseException => ex
            logger.warn("Can't send XMPP alert as valid XHTML-IM, falling back to plaintext")
            logger.debug(ex)
          end

          logger.debug "Jabber sending #{message} to #{destination}"
          reconnect unless @client

          ensure_roster_and_subscription!(dest_jid) unless destination_is_muc

          if conditions && !check_alert_conditions(dest_jid, conditions) 
            logger.debug("Alert conditions not met, not sending XMPP alert to #{jid}")
            return false
          end

          if destination_is_muc
            if !@mucs[dest_jid]
              @mucs[dest_jid] = CountingMUCClient.new(@client)
              @mucs[dest_jid].join(JID.new(dest_jid))
            end
            reconnect_and_retry_on_error { @mucs[dest_jid].send(message, nil) ; true }
          else
            message.to = dest_jid
            reconnect_and_retry_on_error { @client.send(message) ; true }
          end            
        end

        # Sends a message to the destionation.
        #
        # @param [String] destionation The (full) JID to send to.
        # @param [String] msg The (formatted) message to send.
        # @return [NIL] nada.
        def send_msg(destination, msg)
          reconnect unless @client
          message = Message.new(nil, msg)
          destination_is_muc, dest_jid = self.is_muc?(destination)
          if destination_is_muc
            if !@mucs[dest_jid]
              @mucs[dest_jid] = CountingMUCClient.new(@client)
              @mucs[dest_jid].join(JID.new(dest_jid))
            end
            reconnect_and_retry_on_error { @mucs[dest_jid].send(message, nil) ; true }
          else
            message.to = dest_jid
            reconnect_and_retry_on_error { @client.send(message) ; true }
          end
          return nil
        end

        protected

        # Checks whether the destination JID is a MUC. 
        # Returns [true/false, destination]
        def is_muc?(destination)
          if /^muc:(.*)/.match(destination)
            [true, $1]
          else
            [false, destination]  
          end
        end
        
        # Checks to see if the JID is in our roster, and whether we are
        # subscribed to it or not. Will add to the roster and subscribe as
        # is necessary to ensure both are true.
        def ensure_roster_and_subscription!(jid)
          jid = JID.new(jid)
          ri = @roster.find(jid)[jid]
          if ri.nil? 
            @roster.add(jid, nil, true)
          else  
            ri.subscribe unless [:to, :both, :remove].include?(ri.subscription)
          end  
        rescue Exception => ex
          logger.error("Problem ensuring that #{jid} is subscribed and in mauve's roster: #{ex.inspect}")
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
        def check_jid_has_presence(jid, presence_or_presences)
          return true if jid.match(/^muc:/)

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
        
      end
    end
  end
end


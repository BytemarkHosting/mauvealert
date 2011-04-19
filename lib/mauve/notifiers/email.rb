require 'time'
require 'net/smtp'
require 'rmail'
require 'mauve/notifiers/debug'

module Mauve
  module Notifiers
    module Email
    
      
      class Default        
        attr_reader :name
        attr :server, true
        attr :port, true
        attr :username, true
        attr :password, true
        attr :login_method, true
        attr :from, true
        attr :subject_prefix, true
        attr :email_suffix, true
        
        def username=(username)
          @login_method ||= :plain
          @username = username
        end
        
        def initialize(name)
          @name = name
          @server = '127.0.0.1'
          @port = 25
          @username = nil
          @password = nil
          @login_method = nil
          @from = "mauve@localhost" 
          @hostname = "localhost"
          @signature = "This is an automatic mailing, please do not reply."
          @subject_prefix = ""
          @suppressed_changed = nil
        end

        def send_alert(destination, alert, all_alerts, conditions = nil)
          message = prepare_message(destination, alert, all_alerts, conditions)
          args  = [@server, @port]
          args += [@username, @password, @login_method.to_sym] if @login_method
          begin
            Net::SMTP.start(*args) do |smtp|
              smtp.send_message(message, @from, destination)
            end
          rescue Errno::ECONNREFUSED => e
            @logger = Log4r::Logger.new "mauve::email_send_alert"
            @logger.error("#{e.class}: #{e.message} raised. " +
                          "args = #{args.inspect} "
                         )
            raise e
          rescue => e
            raise e
          end
        end
        
        protected
        
        def prepare_message(destination, alert, all_alerts, conditions = nil)
          if conditions
            @suppressed_changed = conditions[:suppressed_changed]
          end
          
          other_alerts = all_alerts - [alert]
          
          m = RMail::Message.new
          
          m.header.subject = subject_prefix + 
            case @suppressed_changed
            when true
              "Suppressing notifications (#{all_alerts.length} total)"
            
            else
              alert.summary_one_line.to_s 
          end
          m.header.to = destination
          m.header.from = @from
          m.header.date = MauveTime.now

          summary_formatted = "  * "+alert.summary_two_lines.join("\n  ")
                    
          case alert.update_type.to_sym
            when :cleared
              m.body = "An alert has been cleared:\n"+summary_formatted+"\n\n"
            when :raised
              m.body = "An alert has been raised:\n"+summary_formatted+"\n\n"
            when :acknowledged
              m.body = "An alert has been acknowledged by #{alert.acknowledged_by}:\n"+summary_formatted+"\n\n"
            when :changed
              m.body = "An alert has changed in nature:\n"+summary_formatted+"\n\n"
            else
              raise ArgumentError.new("Unknown update_type #{alert.update_type}")
          end
          
          # FIXME: include alert.detail as multipart mime
          ##Thread.abort_on_exception = true
          m.body += "\n" + '-'*10 + " This is the detail field " + '-'*44 + "\n\n"
          m.body += alert.get_details()
          m.body += alert.get_details_plain_text()
          m.body += "\n" + '-'*80 + "\n\n"
          
          if @suppressed_changed == true
            m.body += <<-END
IMPORTANT: I've been configured to suppress notification of individual changes
to alerts until their rate decreases.  If you still need notification of evrey
single alert, you must watch the web front-end instead.

            END
          elsif @suppressed_changed == false
            m.body += "(Notifications have slowed down - you will now be notified of every change)\n\n"
          end
          
          if other_alerts.empty?
            m.body += (alert.update_type == :cleared ? "That was" : "This is")+
              " currently the only alert outstanding\n\n"
          else
            m.body += other_alerts.length == 1 ? 
              "There is currently one other alert outstanding:\n\n" :
              "There are currently #{other_alerts.length} other alerts outstanding:\n\n"
            
            other_alerts.each do |other|
              m.body += "  * "+other.summary_two_lines.join("\n  ")+"\n\n"
            end
          end
          
          m.body += "-- \n"+@signature
          
          m.to_s
        end
        include Debug
      end
    end
  end
end

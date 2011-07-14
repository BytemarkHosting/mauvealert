require 'time'
require 'net/smtp'
require 'rmail'
require 'mauve/notifiers/debug'

module Mauve
  module Notifiers
    module Email
    
      class Default
        attr_reader :name
        attr_writer :server, :port, :password, :login_method, :from, :subject_prefix, :email_suffix
        
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

        def logger
          @logger ||= Log4r::Logger.new self.class.to_s.sub(/::Default$/,"")

        end

        def send_alert(destination, alert, all_alerts, conditions = {})
          message = prepare_message(destination, alert, all_alerts, conditions)
          args  = [@server, @port]
          args += [@username, @password, @login_method.to_sym] if @login_method

          begin
            Net::SMTP.start(*args) do |smtp|
              smtp.send_message(message, @from, destination)
            end
            true
          rescue StandardError => ex
            logger.error "SMTP failure: #{ex.to_s}"
            logger.debug ex.backtrace.join("\n")
            false
          end
        end
        
        protected
        
        def prepare_message(destination, alert, all_alerts, conditions = {})
          was_suppressed = conditions[:was_suppressed] || false
          is_suppressed  = conditions[:is_suppressed]  || false
          
          m = RMail::Message.new
         
          #
          # Use a template for:
          #
          #   * The subject
          #   * The text part
          #   * The HTML part.
          #
          subject_template = File.join(File.dirname(__FILE__), "templates", "email_subject.txt.erb")
          if File.exists?(subject_template)
            m.header.subject = ERB.new(File.read(subject_template)).result(binding).chomp
          else
            m.header.subject = "Arse"
          end

          m.header.to = destination
          m.header.from = @from
          m.header.date = MauveTime.now
          m.header['Content-Type'] = "multipart/alternative"

          txt_template = File.join(File.dirname(__FILE__), "templates", "email.txt.erb")
          if File.exists?(txt_template)
            txt = RMail::Message.new
            txt.header['Content-Type'] = "text/plain; charset=\"utf-8\""
            txt.body = ERB.new(File.read(txt_template)).result(binding).chomp
            m.add_part(txt)
          end

          html_template = File.join(File.dirname(__FILE__), "templates", "email.html.erb")
          if File.exists?(html_template)
            html = RMail::Message.new
            html.header['Content-Type'] = "text/html; charset=\"utf-8\""
            html.body = ERB.new(File.read(html_template)).result(binding).chomp
            m.add_part(html)
          end

          m.to_s
        end
        include Debug
      end
    end
  end
end

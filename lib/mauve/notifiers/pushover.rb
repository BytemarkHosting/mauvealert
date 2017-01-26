require 'mauve/notifiers/debug'

module Mauve
  module Notifiers
    require 'net/https'
    require 'json'
    require 'cgi'
    require 'uri'

    class Pushover

      attr_accessor :token
      attr_reader   :name

      def initialize(name)
        @name = name
      end

      def gateway
        @gateway
      end

      def gateway=(uri)
        @gateway = URI.parse(uri)
      end

      def send_alert(destination, alert, all_alerts, conditions = {})
        msg = prepare_message(destination, alert, all_alerts, conditions)

        priority = case alert.level
          when :urgent
            1
          when :normal
            0
          else
            -1
        end
        
        opts = {
          "priority" => priority,
          "message" => msg,
          "url" => WebInterface.url_for(alert),
          "url_title" => "View alert",
          "html" => 1,
        }

        uri = @gateway.dup
        uri.path = "/1/messages.json"

        #
        # If the destination is an email, it is a user
        #
        if destination =~ /@/
          (device,user) = destination.split(/@/,2)
          opts['device'] = device
          opts['user'] = user
        else
          opts['user'] = user
        end

        uri.query = "auth_token="+CGI::escape(self.token)

        http = Net::HTTP.new(uri.host, uri.port)

        if uri.port == 443
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
        
        case alert.update_type
        when "cleared"
         opts['timestamp'] = alert.cleared_at
        when "acknowledged"
          opts['timestamp'] = alert.acknowledged_at
        else
          opts['timestamp'] = alert.raised_at
        end 

        response, data = http.post(uri.request_uri, opts, {
          'Content-Type' => 'application/json',
          'Content-Length' => opts.length.to_s
        })
        
        if response.kind_of?(Net::HTTPSuccess)
          #
          # Woo -- return true!
          #
          true
        else
          false
        end

      end
      
      protected

      def prepare_message(destination, alert, all_alerts, conditions={})
        was_suppressed = conditions[:was_suppressed] || false
        will_suppress  = conditions[:will_suppress]  || false
        
        template_file = File.join(File.dirname(__FILE__),"templates","pushover.html.erb")

        txt = if File.exists?(template_file)
          ERB.new(File.read(template_file)).result(binding).chomp
        else
          logger.error("Could not find #{template_file} template")
          alert.to_s
        end
      end
      
    end
  end
end


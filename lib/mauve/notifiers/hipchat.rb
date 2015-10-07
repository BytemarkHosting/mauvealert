require 'mauve/notifiers/debug'

module Mauve
  module Notifiers
    require 'net/https'
    require 'json'
    require 'cgi'
    require 'uri'

    class Hipchat

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

        colour = case alert.level
          when :urgent
            "red"
          when :normal
            "yellow"
          else
            "green"
        end
        
        opts = {
          "color"   => colour,
          "message" => msg,
          "notify"  => true,
        }


        uri = @gateway.dup

        #
        # If the destination is an email, it is a user
        #
        if destination =~ /@/
          uri.path = "/v2/user/"+ CGI::escape(destination) +"/message"
          opts["message_type"] = "text"
        else
          uri.path = "/v2/room/"+CGI::escape(destination)+"/notification"
          opts["message_type"] = "html"
        end

        uri.query = "auth_token="+CGI::escape(self.token)

        http = Net::HTTP.new(uri.host, uri.port)

        if uri.port == 443
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
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
        
        if destination =~ /@/
          template_file = File.join(File.dirname(__FILE__),"templates","hipchat.txt.erb")
        else
          template_file = File.join(File.dirname(__FILE__),"templates","hipchat.html.erb")
        end

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


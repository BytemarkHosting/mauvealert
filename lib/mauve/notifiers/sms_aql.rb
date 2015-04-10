require 'mauve/notifiers/debug'
require 'cgi'

module Mauve
  module Notifiers
    module Sms
      
      require 'net/https'

      # Simple SMS-sending wrapper.  Use like so:
      # 
      #   aql = Mauve::Notifiers::Sms::AQLGateway.new(username, password)
      #   aql.send_sms(to_number="077711234567",
      #                from_number="0190412345678",
      #                message="This is my message!")
      class AQLGateway
        GATEWAY = "https://gw1.aql.com/sms/sms_gw.php"

        def initialize(username, password)
          @username = username
          @password = password
        end

        def send_sms(destination, from, message, flash=0)
          uri = URI.parse(GATEWAY)

          opts_string = {
            :username => @username,
            :password => @password,
            :destination => destination,
            :message => message,
            :originator => @from,
            :flash => flash
          }.map { |k,v| "#{k}=#{CGI::escape(v.to_s)}" }.join("&")
          
          http = Net::HTTP.new(uri.host, uri.port)
          if uri.port == 443
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end
          response, data = http.post(uri.path, opts_string, {
            'Content-Type' => 'application/x-www-form-urlencoded',
            'Content-Length' => opts_string.length.to_s
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
      end # class AQLGateway


      class AQL

        attr_writer :username, :password, :from
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def send_alert(destination, alert, all_alerts, conditions = {})
          to = normalize_number(destination)
          msg = prepare_message(destination, alert, all_alerts, conditions)
          AQLGateway.new(@username, @password).send_sms(to, @from, msg)
        end
        
        protected
        def prepare_message(destination, alert, all_alerts, conditions={})
          was_suppressed = conditions[:was_suppressed] || false
          will_suppress  = conditions[:will_suppress]  || false
          
          template_file = File.join(File.dirname(__FILE__),"templates","sms.txt.erb")

          txt = if File.exists?(template_file)
            ERB.new(File.read(template_file)).result(binding).chomp
          else
            logger.error("Could not find sms.txt.erb template")
            alert.to_s
          end
        end
        
        def normalize_number(n)
          n.split("").select { |s| (?0..?9).include?(s[0]) }.join.gsub(/^0/, "44")
        end
      end
    end
  end
end


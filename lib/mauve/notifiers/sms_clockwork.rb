require 'mauve/notifiers/debug'
require 'cgi'

module Mauve
  module Notifiers
    module Sms
      
      require 'net/https'

      class Clockwork
        GATEWAY = "https://api.clockworksms.com/http/send.aspx"

        attr_writer :apikey, :from
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def send_alert(destination, alert, all_alerts, conditions = {})
          uri = URI.parse(GATEWAY)

          opts_string = {
            :key => @apikey,
            :to => normalize_number(destination),
            :content => prepare_message(destination, alert, all_alerts, conditions),
            :from => @from,
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


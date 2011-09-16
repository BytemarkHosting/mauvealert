# encoding: UTF-8
require 'log4r'
require 'net/http'
require 'net/https'
require 'uri'

module Mauve

  # Interface to the Bytemark calendar.
  #
  class CalendarInterface 
    
    class << self

      # @return [Log4r::Logger]
      def logger
        @logger ||= Log4r::Logger.new(self.to_s)
      end

      # Gets a list of ssologin on support.
      #
      # @param [String] url A Calendar API url.
      #
      # @return [Array] A list of all the usernames on support.
      def get_users_on_support(url)
        result = do_get_with_cache(url)

        if result.is_a?(String)
          result = result.split("\n")
        else
          result = []
        end

        return result
      end

      # Check to see if the user is on support.
      #
      # @param [String] url A Calendar API url.
      # @param [String] usr User single sign on.
      #
      # @return [Boolean] True if on support, false otherwise.
      def is_user_on_support?(url, usr)
        return get_users_on_support(url).include?(usr)
      end

      # Check to see if the user is on holiday.
      #
      # Class method.
      #
      # @param [String] url A Calendar API url.
      # @param [String] usr User single sign on.
      # 
      # @return [Boolean] True if on holiday, false otherwise.
      def is_user_on_holiday?(url)
        result = do_get_with_cache(url)

        if result.is_a?(String) and result =~ /^\d{4}(-\d\d){2}[ T](\d\d:){2}\d\d/
          return true
        else
          return false
        end
      end

    
      private

      # Grab a URL from the wide web.
      #
      # @todo boot this in its own class since list of ips will need it too.
      #
      # @param [String] uri -- a URL
      # @return [String or nil] -- the contents of the URI or nil if an error has been encountered.
      #
      def do_get (uri, limit = 11)

        if 0 == limit
          logger.warn("HTTP redirect too deep for #{uri}.")
          return nil
        end
        
        begin
          uri = URI.parse(uri) unless uri.is_a?(URI::HTTP)

          raise ArgumentError, "#{uri_str.inspect} doesn't look like an HTTP uri" unless uri.is_a?(URI::HTTP)

          http = Net::HTTP.new(uri.host, uri.port)

          #
          # Five second timeouts.
          #
          http.open_timeout = http.read_timeout = 5
 
          if (uri.scheme == "https")
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end

          response = http.start { http.get(uri.request_uri()) }

          if response.is_a?(Net::HTTPOK)
            return response.body

          elsif response.is_a?(Net::HTTPRedirection) and response.key?('Location')
            location = response['Location']
            
            #
            # Bodge locations..
            #
            if location =~ /^\//
              location = uri.class.build([uri.userinfo, uri.host, uri.port, nil, nil, nil]).to_s + location
            end

            return do_get(location, limit-1) 

          else
            logger.warn("Request to #{uri.to_s} returned #{response.code} #{response.message}.")
            return nil

          end

        rescue Timeout::Error => ex
          logger.error("Timeout caught during fetch of #{uri.to_s}.")

        rescue StandardError => ex
          logger.error("#{ex.class} caught during fetch of #{uri.to_s}: #{ex.to_s}.")
          logger.debug(ex.backtrace.join("\n"))

        end

        return nil
      end

      # This does HTTP fetches with a 5 minute cache
      #
      # @param [String] url
      # @param [Time] cache_until
      #
      # @return [String or nil]
      def do_get_with_cache(url, cache_until = Time.now + 5.minutes)
        @cache ||= {}

        if @cache.has_key?(url.to_s)
          result, cache_until = @cache[url.to_s]

          return result if cache_until >= Time.now and not result.nil?
        end

        result = do_get(url)
        @cache[url] = [result, cache_until] unless result.nil?

        return result
      end

    end

  end

end

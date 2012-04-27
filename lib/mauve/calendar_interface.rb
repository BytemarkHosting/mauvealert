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

      def get_attendees(klass, at=Time.now)
        #
        # Returns nil if no calendar_url has been set.
        #
        return [] unless Configuration.current.bytemark_calendar_url
  
        url = Configuration.current.bytemark_calendar_url.dup

        url.merge!(File.join(url.path, "/api/attendees/#{klass}/#{at.strftime("%Y-%m-%dT%H:%M:00")}"))
        ans = do_get(url)

        return [] unless ans.is_a?(Array)

        ans.select{|x| x.is_a?(String)}
      end

      #
      # This should return a list of dates of forthcoming bank holidays
      #
      def get_bank_holiday_list(at = Time.now)
        return [] unless Configuration.current.bytemark_calendar_url

        url = Configuration.current.bytemark_calendar_url.dup
        url.merge!(File.join(url.path, "/api/bank_holidays/#{at.strftime("%Y-%m-%d")}"))
        ans = do_get(url)

        return [] unless ans.is_a?(Array)
        ans.select{|x| x.is_a?(Date)}
      end

      # Check to see if the user is on holiday.
      #
      # Class method.
      #
      # @param [String] usr User single sign on.
      # 
      # @return [Boolean] True if on holiday, false otherwise.
      def is_user_on_holiday?(usr, at=Time.now)
        get_attendees("staff_holiday").include?(usr)
      end

      # Check to see if the user is on holiday.
      #
      # Class method.
      #
      # @param [String] usr User single sign on.
      # 
      # @return [Boolean] True if on holiday, false otherwise.
      def is_user_off_sick?(usr, at=Time.now)
        get_attendees("sick_period", at).include?(usr)
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

        if 0 > limit
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
          http.open_timeout = http.read_timeout = Configuration.current.remote_http_timeout || 5
 
          if (uri.scheme == "https")
            http.use_ssl     = true
            http.ca_path     = "/etc/ssl/certs/" if File.directory?("/etc/ssl/certs")
            http.verify_mode = Configuration.current.remote_https_verify_mode || OpenSSL::SSL::VERIFY_NONE
          end

          response = http.start { http.get(uri.request_uri()) }

          if response.is_a?(Net::HTTPOK)
            #
            # Parse the string as YAML.
            #
            result = if response.body.is_a?(String)
              begin
                YAML.load(response.body)
              rescue YAML::Error => err
                logger.error "Caught #{ex.class.to_s} (#{ex.to_s}) whilst querying #{url.to_s}."
                logger.debug err.backtrace.join("\n")
                nil
              end
            else
              nil
            end

            return result
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
          pp ex.backtrace
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

        if @cache.has_key?(url)
          result, cached_until = @cache[url]

          return result if cached_until > Time.now and not result.nil?
        end

        result = do_get(url)
        @cache[url] = [result, cache_until] unless result.nil?

        return result
      end

      #
      # This should get called periodically.
      #
      def clean_cache

        @cache.keys.select do |url|
          result, cached_until = @cache[url]
          @cache.delete(url) if !cached_until.is_a?(Time) or cached_until <= Time.now
        end

        @cache 
      end

    end

  end

end

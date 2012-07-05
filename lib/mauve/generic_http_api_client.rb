# encoding: UTF-8
require 'log4r'
require 'net/http'
require 'net/https'
require 'uri'

module Mauve

  #
  # This is a generic client that can talk HTTP to other apps to get data.
  #
  module GenericHttpApiClient

    # return [Log4r::Logger]
    def logger
      @logger ||= Log4r::Logger.new(self.to_s)
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
          result = (response.body.is_a?(String) ? response.body : nil)

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

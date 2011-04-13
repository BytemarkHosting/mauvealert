# encoding: UTF-8
require 'log4r'
require 'net/http'
require 'net/https'
require 'uri'

module Mauve

  # Interface to the Bytemark calendar.
  #
  # Nota Bene that this does not include a chaching mechanism.  Some caching
  # is implemented in the Person object.
  #
  # @see Mauve::Person
  # @author yann Golanski.
  class CalendarInterface 
    
    TIMEOUT = 7

    public

    # Gets a list of ssologin on support.
    #
    # Class method.
    #
    # @param [String] url A Calendar API url.
    # @return [Array] A list of all the username on support.
    def self.get_users_on_support(url)
      result = get_URL(url)
      logger = Log4r::Logger.new "mauve::CalendarInterface"
      logger.debug("Cheching who is on support: #{result}")
      return result 
    end

    # Check to see if the user is on support.
    #
    # Class method.
    #
    # @param [String] url A Calendar API url.
    # @param [String] usr User single sign on.
    # @return [Boolean] True if on support, false otherwise.
    def self.is_user_on_support?(url, usr)
      logger = Log4r::Logger.new "mauve::CalendarInterface"
      list = get_URL(url)
      if true == list.include?("nobody")
        logger.error("Nobody is on support thus alerts are ignored.")
        return false
      end
      result = list.include?(usr)
      logger.debug("Cheching if #{usr} is on support: #{result}")
      return result
    end

    # Check to see if the user is on holiday.
    #
    # Class method.
    #
    # @param [String] url A Calendar API url.
    # @param [String] usr User single sign on.
    # @return [Boolean] True if on holiday, false otherwise.
    def self.is_user_on_holiday?(url, usr)
      list = get_URL(url)
      return false if true == list.nil? or true == list.empty?
      pattern = /[\d]{4}-[\d]{2}-[\d]{2}\s[\d]{2}:[\d]{2}:[\d]{2}/
      result = (list[0].match(pattern))? true : false
      logger = Log4r::Logger.new "mauve::CalendarInterface"
      logger.debug("Cheching if #{usr} is on holiday: #{result}")
      return result
    end

  
    private

    # Gets a URL from the wide web.
    #
    # Must NOT crash Mauveserver.
    #
    # Class method.
    #
    # @TODO: boot this in its own class since list of ips will need it too.
    #
    # @param [String] url A Calendar API url.
    # @retur [Array] An array of strings, each newline creates an new item.
    def self.get_URL (uri_str, limit = 11)

      logger = Log4r::Logger.new "mauve::CalendarInterface"
      
      if 0 == limit
        logger.warn("HTTP redirect deeper than 11 on #{uri_str}.")
        return false
      end
      
      begin
        uri_str = 'http://' + uri_str unless uri_str.match(uri_str) 
        url = URI.parse(uri_str)
        http = Net::HTTP.new(url.host, url.port)
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT
        if (url.scheme == "https")
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        response = nil
        if nil == url.query
          response = http.start { http.get(url.path) }
        else
          response = http.start { http.get("#{url.path}?#{url.query}") }
        end
        case response
        when Net::HTTPRedirection
          then
          newURL = response['location'].match(/^http/)?
            response['Location']:
            uri_str+response['Location']
          self.getURL(newURL, limit-1)
        else
          return response.body.split("\n")
        end
      rescue Errno::EHOSTUNREACH => ex
        logger.warn("no route to host.")
        return Array.new
      rescue MauveTimeout::Error => ex
        logger.warn("time out reached.")
        return Array.new
      rescue ArgumentError => ex
        unless uri_str.match(/\/$/)
          logger.debug("Potential missing '/' at the end of hostname #{uri_str}")
          uri_str += "/"
          retry
        else
          str = "ArgumentError raise: #{ex.message} #{ex.backtrace.join("\n")}"
          logger.fatal(str)
          return Array.new
          #raise ex
        end
      rescue => ex
        str = "ArgumentError raise: #{ex.message} #{ex.backtrace.join("\n")}"
        logger.fatal(str)
        return Array.new
        #raise ex
      end

    end
  end

end

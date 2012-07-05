# encoding: UTF-8
require 'mauve/generic_http_api_client'

module Mauve

  # Interface to the Bytemark calendar.
  #
  class CalendarInterface  
    
    class << self

      include GenericHttpApiClient

      # return [Log4r::Logger]
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
        ans = do_get_yaml(url)

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
        ans = do_get_yaml(url)

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

      def do_get_yaml(url)
        resp = do_get(url)

        return (resp.is_a?(String) ? YAML.load(resp) : nil)
      rescue StandardError => ex
        logger.error "Caught #{ex.class.to_s} (#{ex.to_s}) whilst querying #{url.to_s}."
        logger.debug err.backtrace.join("\n")
        nil
      end

    end

  end

end

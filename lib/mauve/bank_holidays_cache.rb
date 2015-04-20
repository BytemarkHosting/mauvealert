require 'mauve/calendar_interface'

module Mauve

  class BankHolidaysCache
    def initialize
      @bank_holidays = []
      @last_checked_at = nil
    end

    def bank_holidays
      now = Time.now
      #
      # Update the bank holidays list hourly.
      #
      if @bank_holidays.nil? or
         @last_checked_at.nil? or
         @last_checked_at < (now - 1.hour)

        @bank_holidays = CalendarInterface.get_bank_holiday_list(now)
        @last_checked_at = now
      end

      @bank_holidays
    end
  end # class BankHolidaysCache

end # module Mauve

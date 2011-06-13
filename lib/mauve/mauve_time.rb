
require 'time'

module Mauve

  class MauveTime < Time
      
    def to_s
      self.iso8601
    end

    def to_s_relative(now = MauveTime.now)
      diff = (self.to_f - now.to_f).to_i
      case diff
        when -5184000..-17200 then "in #{-diff/86400} days"
        when -172799..-3600 then "in #{-diff/3600} hours"
        when -3599..-300 then "in #{-diff/60} minutes"
        when -299..-1 then "very soon"
        when 0..299 then "just now"
        when 300..3599 then "#{diff/60} minutes ago"
        when 3600..172799 then "#{diff/3600} hours ago"
        when 172800..5184000 then "#{diff/86400} days ago"
        else
          diff > 518400 ?
            "#{diff/2592000} months ago" :
            "in #{-diff/2592000} months"
      end
    end

  end

end



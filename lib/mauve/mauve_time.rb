
require 'time'

module Mauve

  class MauveTime < Time
      
    def to_s
      self.iso8601
    end

  end

end



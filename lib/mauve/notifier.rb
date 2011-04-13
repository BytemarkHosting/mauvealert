require 'mauve/mauve_thread'
require 'mauve/notifiers'
require 'mauve/notifiers/xmpp'

module Mauve

  class Notifier < MauveThread

    DEFAULT_XMPP_MESSAGE = "Mauve server started."
    
    include Singleton

    attr_accessor :buffer, :sleep_interval

    def initialize
      @buffer = Queue.new
    end

    def main_loop

      # 
      # Cycle through the buffer.
      #
      sz = @buffer.size
  
      logger.debug("Notifier buffer is #{sz} in length") if sz > 1 

      (sz > 10 ? 10 : sz).times do
        person, level, alert = @buffer.pop
        begin
          person.do_send_alert(level, alert) 
        rescue StandardError => ex
          logger.debug ex.to_s
          logger.debug ex.backtrace.join("\n")
        end
      end

    end

    def start
      super

      Configuration.current.notification_methods['xmpp'].connect if Configuration.current.notification_methods['xmpp']
    end

    def stop
      Configuration.current.notification_methods['xmpp'].close

      super
    end

    class << self

      def enq(a)
        instance.buffer.enq(a)
      end

      alias push enq

    end

  end

end



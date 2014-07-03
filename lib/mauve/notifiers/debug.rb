require 'fileutils'

module Mauve
  module Notifiers
    #
    # The Debug module adds two extra parameters to a notification method
    # for debugging and testing.
    #
    module Debug
      class << self
        def included(base)
          base.class_eval do
            alias_method :send_alert_without_debug, :send_alert
            alias_method :send_alert, :send_alert_to_debug_channels
          end
        end
       
        def extended(base)
          base.instance_eval do
            alias :send_alert_without_debug :send_alert
            alias :send_alert :send_alert_to_debug_channels
          end
        end 
      end


      # Specifying deliver_to_file allows the administrator to ask for alerts
      # to be delivered to a particular file, which is assumed to be perused
      # by a person rather than a machine.
      #
      def deliver_to_file
        @deliver_to_file
      end

      def deliver_to_file=(fn)
        @deliver_to_file = fn
      end

      # Specifying deliver_to_queue allows a tester to ask for the send_alert
      # parameters to be appended to a Queue object (or anything else that 
      # responds to <<).
      # 
      def deliver_to_queue
        @deliver_to_queue
      end

      def deliver_to_queue=(q)
        @deliver_to_queue = q
      end

      def disable_normal_delivery!
        @disable_normal_delivery = true
      end
      
      def send_alert_to_debug_channels(destination, alert, all_alerts, conditions = nil)
        message = if self.respond_to?(:prepare_message)
          prepare_message(destination, alert, all_alerts, conditions)
        else
          [destination, alert, all_alerts].inspect
        end
        
        if deliver_to_file
          File.open("#{deliver_to_file}", "a+") do |fh|
            fh.flock(File::LOCK_EX)
            fh.print YAML.dump([Time.now, self.class, destination, message])
            fh.flush()
          end
        end
        
        deliver_to_queue << [Time.now, self.class, destination, message] if deliver_to_queue
        
        if @disable_normal_delivery
          true # pretend it happened OK if we're just testing
        else
          send_alert_without_debug(destination, alert, all_alerts, conditions)
        end
      end
      
    end
  end
end


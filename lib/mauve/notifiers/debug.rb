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
            
            # Specifying deliver_to_file allows the administrator to ask for alerts
            # to be delivered to a particular file, which is assumed to be perused
            # by a person rather than a machine.
            #
            attr :deliver_to_file, true
            
            # Specifying deliver_to_queue allows a tester to ask for the send_alert
            # parameters to be appended to a Queue object (or anything else that 
            # responds to <<).
            # 
            attr :deliver_to_queue, true
          end
        end
      end
      
      def disable_normal_delivery!
        @disable_normal_delivery = true
      end
      
      def send_alert_to_debug_channels(destination, alert, all_alerts, conditions = nil)
        message = if respond_to?(:prepare_message)
          prepare_message(destination, alert, all_alerts, conditions)
        else
          [destination, alert, all_alerts].inspect
        end
        
        if deliver_to_file
          #lock_file = "#{deliver_to_file}.lock"
          #while File.exists?(lock_file)
          #  sleep 0.1
          #end
          #FileUtils.touch(lock_file)
          File.open("#{deliver_to_file}", "a+") do |fh|
            fh.flock(File::LOCK_EX)
            fh.print("#{Time.now} from #{self.class}: " + message + "\n")
            fh.flush()
          end
          #FileUtils.rm(lock_file)
        end
        
        deliver_to_queue << [destination, alert, all_alerts, conditions] if deliver_to_queue
        
        if  @disable_normal_delivery
          true # pretend it happened OK if we're just testing
        else
          send_alert_without_debug(destination, alert, all_alerts, conditions)
        end
      end
      
    end
  end
end


# encoding: UTF-8
require 'mauve/datamapper'
require 'log4r'

module Mauve
  class AlertChanged
    include DataMapper::Resource
    
    # so .first always returns the most recent update
    default_scope(:default).update(:order => [:at.desc, :id.desc])
    
    property :id, Serial
    property :alert_id, Integer, :required  => true
    property :person, String, :required  => true
    property :at, Time, :required => true
    property :was_relevant, Boolean, :required => true, :default => true
    property :level, String, :required  => true
    property :update_type, String, :required  => true
    property :remind_at, Time
    # property :updated_at, Time, :required => true

    def inspect
      "#<AlertChanged #{id}: alert_id #{alert_id}, for #{person}, update_type #{update_type}>"
    end

    alias to_s inspect
    
    belongs_to :alert
    
    def was_relevant=(value)
      attribute_set(:was_relevant, value)
    end

    def updated_at
      self.at
    end
    
    def updated_at=(t)
      self.at = t
    end

    def logger
     Log4r::Logger.new self.class.to_s
    end

    # Sends a reminder about this alert state change, or forget about it if
    # the alert has been acknowledged
    #
    def remind
      unless alert.is_a?(Alert)
        logger.info "#{self.inspect} lost alert #{alert_id}.  Killing self."
        destroy!
        return false
      end
      
      if !alert_group 
        logger.info("No alert group matches any more.  Clearing reminder for #{self.alert}.")
        self.remind_at = nil
        return save
      end


      if alert.acknowledged?
        logger.info("Alert already acknowledged.  Clearing reminder due for #{self.alert}.")
        self.remind_at = nil
        return save
      end

      #
      # Postpone reminders from previous runs, if needed.
      #
      if Server.instance.in_initial_sleep? and
          self.at < Server.instance.started_at

        self.remind_at = Server.instance.started_at + Server.instance.initial_sleep
        logger.info("Postponing reminder for #{self.alert} until #{self.remind_at} since this reminder was updated in a prior run of Mauve.")
        return save
      end

      alert_group.notify(alert)
      #
      # Need to make sure this reminder is cleared.
      #
      self.remind_at = nil

      save
    end
    
    def due_at # mimic interface from Alert
      remind_at ? remind_at : nil
    end
    
    def poll # mimic interface from Alert
      logger.debug("Polling #{self.to_s}")
      remind if remind_at.is_a?(Time) and remind_at <= Time.now
    end

    def alert_group
      alert.alert_group
    end
    
    class << self
      def next_reminder
        first(:remind_at.not => nil, :order => [:remind_at])
      end
      
      def find_next_with_event # mimic interface from Alert
        next_reminder
      end

      def all_overdue(at = Time.now)
        all(:remind_at.not => nil, :remind_at.lt => at, :order => [:remind_at]).to_a
      end
    end
  end
end

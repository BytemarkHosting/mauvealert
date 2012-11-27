# encoding: UTF-8
require 'mauve/datamapper'
require 'log4r'

module Mauve
  #
  # Class to record changes to alerts.  Also responsible for keeping records for reminders.
  #
  class AlertChanged
    include DataMapper::Resource
    
    # so .first always returns the most recent update
    default_scope(:default).update(:order => [:at.desc, :id.desc])
    
    property :id, Serial
    property :alert_id, Integer, :required  => true
    property :person, String, :required  => true
    property :at, EpochTime, :required => true
    property :was_relevant, Boolean, :required => true, :default => true
    property :level, String, :required  => true
    property :update_type, String, :required  => true
    property :remind_at, EpochTime, :required => false
    
    belongs_to :alert

    before :valid?, :do_set_timestamps

    protected

    def do_set_timestamps(context = :default)
      self.at = Time.now unless self.original_attributes.has_key?("at")
    end

    public

    # @return [String]
    def to_s
      "#<AlertChanged #{id}: alert_id #{alert_id}, for #{person}, update_type #{update_type}>"
    end

    # @deprecated I don't think was_relevant is used any more.
    #
    def was_relevant=(value)
      attribute_set(:was_relevant, value)
    end

    # The time this object was last updated
    # 
    # @return [Time]
    def updated_at
      self.at
    end
    
    # Set the time this object was last updated
    #
    # @param [Time] t
    # @return [Time]
    def updated_at=(t)
      self.at = t
    end

    # @return [Log4r::Logger]
    def logger
     Log4r::Logger.new self.class.to_s
    end

    # Sends a reminder about this alert state change, or forget about it if
    # the alert has been acknowledged
    #
    # @return [Boolean] indicating successful update of the AlertChanged object
    def remind
      unless alert.is_a?(Alert)
        logger.info "#{self.inspect} lost alert #{alert_id}.  Killing self."
        destroy
        return false
      end
      
      if !alert_group 
        logger.info("No alert group matches any more.  Clearing reminder for #{self.alert}.")
        self.remind_at = nil
        return save
      end

      if alert.acknowledged? or alert.cleared?
        logger.info("Alert already acknowledged/cleared.  Clearing reminder due for #{self.alert}.")
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

      #
      # Push this notifitcation onto the queue.
      #
      Server.notification_push([alert, Time.now])

      #
      # Need to make sure this reminder is cleared.
      #
      self.remind_at = nil

      #
      # Now save.
      #
      return self.save
    end
    
    # The time this AlertChanged should next be polled at, or nil.  Mimics
    # interaface from Alert.
    #
    # @return [Time, NilClass]
    def due_at 
      remind_at ? remind_at : nil
    end
    
    # Sends a reminder, if needed. Mimics interaface from Alert.
    #
    # @return [Boolean] showing polling was successful
    def poll # mimic interface from Alert
      logger.debug("Polling #{self.to_s}")

      if remind_at.is_a?(Time) and remind_at <= Time.now
        remind 
      else
        true
      end
    end

    # The AlertGroup for this object
    #
    # @return [Mauve::AlertGroup]
    def alert_group
      alert.alert_group
    end
    
    class << self
      # Finds the next reminder due, or nil if nothing due.
      #
      # @return [Mauve::AlertChanged, NilClass]
      def next_reminder
        first(:remind_at.not => nil, :order => [:remind_at])
      end
      
      # Finds the next event due.  Mimics interface from Alert.
      #
      # @return [Mauve::AlertChanged, NilClass]
      def find_next_with_event 
        next_reminder
      end

      # @deprecated  I don't think this is used any more.
      #
      # @return [Array]
      def all_overdue(at = Time.now)
        all(:remind_at.not => nil, :remind_at.lt => at, :order => [:remind_at]).to_a
      end
    end
  end
end

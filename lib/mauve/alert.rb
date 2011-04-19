require 'mauve/proto'
require 'mauve/alert_changed'
require 'mauve/datamapper'


module Mauve
  class AlertEarliestDate
 
    include DataMapper::Resource
    
    property :id, Serial
    property :alert_id, Integer
    property :earliest, DateTime
    belongs_to :alert, :model => "Alert"
    
    # 1) Shame we can't get this called automatically from DataMapper.auto_upgrade!
    #
    # 2) Can't use a neater per-connection TEMPORARY VIEW because the pooling 
    # function causes the connection to get dropped occasionally, and we can't
    # hook the reconnect function (that I know of).
    #
    # http://www.mail-archive.com/datamapper@googlegroups.com/msg02314.html
    #
    def self.create_view!
      the_distant_future = MauveTime.now + 86400000 # it is the year 2000 - the humans are dead
      ["BEGIN TRANSACTION",
       "DROP VIEW IF EXISTS mauve_alert_earliest_dates",
       "CREATE VIEW 
          mauve_alert_earliest_dates
        AS
        SELECT 
          id AS alert_id,
          NULLIF(
            MIN(
              IFNULL(will_clear_at, '#{the_distant_future}'),
              IFNULL(will_raise_at, '#{the_distant_future}'),
              IFNULL(will_unacknowledge_at,  '#{the_distant_future}')
            ),
            '#{the_distant_future}'
          ) AS earliest
        FROM mauve_alerts 
        WHERE
          will_clear_at IS NOT NULL OR
          will_raise_at IS NOT NULL OR
          will_unacknowledge_at IS NOT NULL
      ",
      "END TRANSACTION"].each do |statement|
        repository(:default).adapter.execute(statement.gsub(/\s+/, " "))
      end
    end

  end
  
  class Alert
    def bytesize; 99; end
    def size; 99; end
    
    include DataMapper::Resource
    
    property :id, Serial
    property :alert_id, String, :required => true, :unique_index => :alert_index, :length=>256
    property :source, String, :required => true, :unique_index => :alert_index, :length=>512
    property :subject, String, :length=>512, :length=>512
    property :summary, String, :length=>1024
    property :detail, Text, :length=>65535
    property :importance, Integer, :default => 50

    property :raised_at, DateTime
    property :cleared_at, DateTime
    property :updated_at, DateTime
    property :acknowledged_at, DateTime
    property :acknowledged_by, String
    property :update_type, String
    
    property :will_clear_at, DateTime
    property :will_raise_at, DateTime
    property :will_unacknowledge_at, DateTime
#    property :will_unacknowledge_after, Integer
    
    has n, :changes, :model => AlertChanged
    has 1, :alert_earliest_date

    validates_with_method :check_dates
    
    def to_s
      "#<Alert:#{id} #{alert_id} from #{source} update_type #{update_type}>"
    end
   
    def check_dates
      bad_dates = self.attributes.find_all do |key, value|
        value.is_a?(DateTime) and not (DateTime.new(2000,1,1,0,0,0)..DateTime.new(2020,1,1,0,0,0)).include?(value)
      end

      if bad_dates.empty?
        true
      else
        [ false, "The dates "+bad_dates.collect{|k,v| "#{v.to_s} (#{k})"}.join(", ")+" are invalid." ]
      end
    end

    default_scope(:default).update(:order => [:source, :importance])
   
    def logger
      Log4r::Logger.new(self.class.to_s)
    end
 
    def time_relative(secs)
      secs = secs.to_i.abs
      case secs
        when 0..59 then "just now"
        when 60..3599 then "#{secs/60}m ago"
        when 3600..86399 then "#{secs/3600}h ago"
        else
          days = secs/86400
          days == 1 ? "yesterday" : "#{secs/86400} days ago"
      end
    end

    def summary_one_line
      subject ? "#{subject} #{summary}" : "#{source} #{summary}"
    end

    def summary_two_lines
      msg = ""
      msg += "from #{source} " if source != subject
      if cleared_at
        msg += "cleared #{time_relative(MauveTime.now - cleared_at.to_time)}"
      elsif acknowledged_at
        msg += "acknowledged #{time_relative(MauveTime.now - acknowledged_at.to_time)} by #{acknowledged_by}"
      else
        msg += "raised #{time_relative(MauveTime.now - raised_at.to_time)}"
      end
      [summary_one_line, msg]
    end

    # Returns a better array with information about the alert.
    #
    # @return [Array] An array of three elements: status, message, source.
    def summary_three_lines
      status = String.new
      if "cleared" == update_type
        status += "CLEARED #{time_relative(MauveTime.now - cleared_at.to_time)}"
      elsif "acknowledged" == update_type
        status += "ACKNOWLEDGED #{time_relative(MauveTime.now - acknowledged_at.to_time)} by #{acknowledged_by}"
      elsif "changed" == update_type
        status += "CHANGED #{time_relative(MauveTime.now - updated_at.to_time)}"
      else
        status += "RAISED #{time_relative(MauveTime.now - raised_at.to_time)}"
      end
      src = (source != subject)?  "from #{source}" : nil
      return [status, summary_one_line, src]
=begin
      status = String.new
      if cleared_at
        status += "CLEARED #{time_relative(MauveTime.now - cleared_at.to_time)}"
      elsif acknowledged_at
        status += "ACKNOWLEDGED #{time_relative(MauveTime.now - acknowledged_at.to_time)} by #{acknowledged_by}"
      else
        status += "RAISED #{time_relative(MauveTime.now - raised_at.to_time)}"
      end
      src = (source != subject)?  "from #{source}" : nil
      return [status, summary_one_line, src]
=end
    end


    def alert_group
      AlertGroup.matches(self)[0]
    end
    
    def subject
      attribute_get(:subject) || source
    end
    
    def subject=(subject); set_changed_if_different(:subject, subject); end
    def summary=(summary); set_changed_if_different(:summary, summary); end
    def detail=(detail); set_changed_if_different(:detail, detail); end
    
    protected
    def set_changed_if_different(attribute, value)
      return if self.__send__(attribute) == value
      self.update_type ||= :changed
      attribute_set(attribute.to_sym, value)
    end
    
    public
    
    def acknowledge!(person)
      self.acknowledged_by = person.username
      self.acknowledged_at = MauveTime.now
      self.update_type = :acknowledged
      self.will_unacknowledge_at = MauveTime.parse(acknowledged_at.to_s) + 
      logger.error("Couldn't save #{self}") unless save
      AlertGroup.notify([self])
    end
    
    def unacknowledge!
      self.acknowledged_by = nil
      self.acknowledged_at = nil
      self.update_type = :raised
      logger.error("Couldn't save #{self}") unless save
      AlertGroup.notify([self])
    end
    
    def raise!
      already_raised = raised? && !acknowledged?
      self.acknowledged_by = nil
      self.acknowledged_at = nil
      self.will_unacknowledge_at = nil
      self.will_raise_at = nil
      self.update_type = :raised
      self.raised_at = MauveTime.now
      self.cleared_at = nil
      logger.error("Couldn't save #{self}") unless save
      AlertGroup.notify([self]) unless already_raised
    end
    
    def clear!(notify=true)
      already_cleared = cleared?
      self.cleared_at = MauveTime.now
      self.will_clear_at = nil
      self.update_type = :cleared
      logger.error("Couldn't save #{self}") unless save
      AlertGroup.notify([self]) unless !notify || already_cleared
    end
      
    # Returns the time at which a timer loop should call poll_event to either
    # raise, clear or unacknowldge this event.
    # 
    def due_at
      o = [will_clear_at, will_raise_at, will_unacknowledge_at].compact.sort[0]
      o ? o.to_time : nil
    end
    
    def poll
      raise! if will_unacknowledge_at && will_unacknowledge_at.to_time <= MauveTime.now ||
        will_raise_at && will_raise_at.to_time <= MauveTime.now
      clear! if will_clear_at && will_clear_at.to_time <= MauveTime.now
    end
    
    def raised?
      !raised_at.nil? && cleared_at.nil?
    end
    
    def acknowledged?
      !acknowledged_at.nil?
    end
    
    def cleared?
      new? || !cleared_at.nil?
    end
    
    class << self
    
      def all_current
        all(:cleared_at => nil)
      end
      
      # Returns the next Alert that will have a timed action due on it, or nil
      # if none are pending.
      #
      def find_next_with_event
        earliest_alert = AlertEarliestDate.first(:order => [:earliest])
        earliest_alert ? earliest_alert.alert : nil
      end

      def all_overdue(at = MauveTime.now)
        AlertEarliestDate.all(:earliest.lt => at, :order => [:earliest]).collect do |earliest_alert|
          earliest_alert ? earliest_alert.alert : nil
        end
      end
     
      # Receive an AlertUpdate buffer from the wire.
      #
      def receive_update(update, reception_time = MauveTime.now)
        update = Proto::AlertUpdate.parse_from_string(update) unless
          update.kind_of?(Proto::AlertUpdate)
        alerts_updated = []
        
        logger.debug("Alert update received from wire: #{update.inspect.split.join(", ")}")
        
        #
        # Transmission time helps us determine any time offset
        #
        if update.transmission_time and update.transmission_time > 0
          transmission_time = MauveTime.at(update.transmission_time) 
        else
          transmission_time = reception_time
        end

        time_offset = (reception_time - transmission_time).round
        logger.debug("Update received from a host #{time_offset}s behind") if time_offset.abs > 0

        # Update each alert supplied
        #
        update.alert.each do |alert|
          # Infer some actions from our pure data structure (hmm, wonder if
          # this belongs in our protobuf-derived class?
          #
          raise_time = alert.raise_time == 0 ? nil : MauveTime.at(alert.raise_time + time_offset)
          clear_time = alert.clear_time == 0 ? nil : MauveTime.at(alert.clear_time + time_offset)

          logger.debug("received at #{reception_time}, transmitted at #{transmission_time}, raised at #{raise_time}, clear at #{clear_time}")

          do_clear = clear_time && clear_time <= reception_time
          do_raise = raise_time && raise_time <= reception_time
            
          alert_db = first(:alert_id => alert.id, :source => update.source) ||
            new(:alert_id => alert.id, :source => update.source)
          
          pre_raised       = alert_db.raised?
          pre_cleared      = alert_db.cleared?
          pre_acknowledged = alert_db.acknowledged?
                    
          alert_db.update_type = nil
          
          ##
          #
          # Allow a 15s offset in timings.
          #
          if raise_time
            if raise_time <= (reception_time + 15)
              alert_db.raised_at = raise_time
            else
              alert_db.will_raise_at = raise_time
            end
          end

          if clear_time
            if clear_time <= (reception_time + 15)
              alert_db.cleared_at = clear_time
            else
              alert_db.will_clear_at = clear_time
            end
          end
          
          # re-raise
          if alert_db.cleared_at && alert_db.raised_at && alert_db.cleared_at < alert_db.raised_at
            alert_db.cleared_at = nil 
          end
          
          if pre_cleared && alert_db.raised?
            alert_db.update_type = :raised
          elsif pre_raised && alert_db.cleared?
            alert_db.update_type = :cleared
          end
            
          # Changing any of these attributes causes the alert to be sent back
          # out to the notification system with an update_type of :changed.
          #
          alert_db.subject = alert.subject if alert.subject && !alert.subject.empty?
          alert_db.summary = alert.summary if alert.summary && !alert.summary.empty?
          alert_db.detail  = alert.detail  if alert.detail  && !alert.detail.empty?

          # These updates happen but do not sent the alert back to the
          # notification system.
          #
          alert_db.importance = alert.importance if alert.importance != 0
  
          # FIXME: this logic ought to be clearer as it may get more complicated
          #
          if alert_db.update_type
            if alert_db.update_type.to_sym == :changed && !alert_db.raised?
              # do nothing
            else
              alerts_updated << alert_db
            end
          else
            alert_db.update_type = :changed
          end

          if !alert_db.save
            if alert_db.errors.respond_to?("full_messages")
              msg = alert_db.errors.full_messages
            else
              msg = alert_db.errors.inspect
            end
            logger.error "Couldn't save update #{alert} because of #{msg}" unless alert_db.save
          end
        end
        
        # If this is a complete replacement update, find the other alerts
        # from this source and clear them.
        #
        if update.replace
          alert_ids_mentioned = update.alert.map { |alert| alert.id }
          logger.debug "Replacing all alerts from #{update.source} except "+alert_ids_mentioned.join(",")
          all(:source => update.source, 
              :alert_id.not => alert_ids_mentioned,
              :cleared_at => nil
              ).each do |alert_db|
            logger.debug "Replace: clearing #{alert_db.id}"
            alert_db.clear!(false)
            alerts_updated << alert_db
          end
        end
        
        AlertGroup.notify(alerts_updated)
      end

      def logger
        Log4r::Logger.new("Mauve::Alert")
      end
    end
  end
end

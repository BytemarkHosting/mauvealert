require 'mauve/proto'
require 'mauve/alert_changed'
require 'mauve/history'
require 'mauve/datamapper'
require 'sanitize'

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
    property :subject, String, :length=>512 
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
    has n, :changes, :model => AlertChanged
    has n, :histories, :model => Mauve::History
    has 1, :alert_earliest_date

    before :save, :take_copy_of_changes
    after  :save, :notify_if_needed

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

    #
    # AlertGroup.matches must always return a an array of groups.
    #
    def alert_group
      @alert_group ||= AlertGroup.matches(self).first
    end

    #
    #
    #
    def level
      @level ||= self.alert_group.level
    end
  
    def sort_tuple
      [AlertGroup::LEVELS.index(self.level), (self.raised_at || self.cleared_at || Time.now).to_time]
    end

    def <=>(other)
      other.sort_tuple <=> self.sort_tuple
    end
 
    def subject; attribute_get(:subject) || attribute_get(:source) || "not set" ; end
    def detail;  attribute_get(:detail)  || "_No detail set._" ; end
 
    # def subject=(subject); set_changed_if_different( :subject, subject ); end
    # def summary=(summary); set_changed_if_different( :summary, summary ); end

    # def source=(source);   attribute_set( :source, source ); end 
    # def detail=(detail);   attribute_set( :detail, detail ); end
    
    protected

    #def set_changed_if_different(attribute, value)
    #  return if self.__send__(attribute) == value
    #  self.update_type ||= "changed"
    #  attribute_set(attribute.to_sym, value)
    #end

    #
    # This allows us to take a copy of the changes before we save.
    #
    def take_copy_of_changes
      @changes_before_save = Hash.new
      self.original_attributes.each do |k,v| 
        @changes_before_save[k.name] = v
      end
    end

    #
    # This sends notifications.  It is called after each save.
    #
    def notify_if_needed
      #
      # Make sure we don't barf
      #
      @changes_before_save ||= Hash.new

      is_a_change = [:subject, :summary].any?{|k| @changes_before_save.keys.include?(k)}

      #
      # We notify if the update type has changed, or if the update type is
      # "raised", and the above is_a_change condition is true
      #
      if @changes_before_save.has_key?(:update_type) or (self.update_type == "raised" and is_a_change)
        self.notify

        h = History.new(:alert => self, :type => "update")

        if self.update_type == "acknowledged"
            h.event = "ACKNOWLEDGED by #{self.acknowledged_by} until #{self.will_unacknowledge_at}"

        elsif is_a_change
          h.event = "CHANGED: "
          h.event += @changes_before_save.keys.collect{|k| "#{k.to_s}: #{@changes_before_save[k]} -> #{self.__send__(k)}"}.join(", ") 

        else
          h.event = self.update_type.upcase

        end

        h.save
      end

      true
    end

    public
    
    def notify
      self.alert_group.notify(self)
    end

    def acknowledge!(person, ack_until = Time.now+3600)
      raise ArgumentError unless person.is_a?(Person)
      raise ArgumentError unless ack_until.is_a?(Time)
      raise ArgumentError, "Cannot acknowledge a cleared alert" if self.cleared?
 
      self.acknowledged_by = person.username
      self.acknowledged_at = MauveTime.now
      self.will_unacknowledge_at = ack_until
      self.update_type = "acknowledged"

      logger.error("Couldn't save #{self}") unless save
    end
    
    def unacknowledge!
      self.acknowledged_by = nil
      self.acknowledged_at = nil
      self.will_unacknowledge_at = nil
      self.update_type = (raised? ? "raised" : "cleared")

      logger.error("Couldn't save #{self}") unless save
    end
    
    def raise!(at = MauveTime.now)
      self.acknowledged_by = nil
      self.acknowledged_at = nil
      self.will_unacknowledge_at = nil
      self.raised_at = at if self.raised_at.nil?
      self.will_raise_at = nil
      self.cleared_at = nil
      # Don't clear will_clear_at
      self.update_type = "raised" if self.update_type.nil? or self.update_type != "changed" or self.original_attributes[Alert.properties[:update_type]] == "cleared"
      
      logger.debug("saving #{self.inspect}")
      logger.error("Couldn't save #{self}") unless save
    end
    
    def clear!(at = MauveTime.now)
      self.acknowledged_by = nil
      self.acknowledged_at = nil
      self.will_unacknowledge_at = nil
      self.raised_at = nil
      # Don't clear will_raise_at
      self.cleared_at = at if self.cleared_at.nil?
      self.will_clear_at = nil
      self.update_type = "cleared"

      logger.error("Couldn't save #{self}") unless save
    end
      
    # Returns the time at which a timer loop should call poll_event to either
    # raise, clear or unacknowldge this event.
    # 
    def due_at
      o = [will_clear_at, will_raise_at, will_unacknowledge_at].compact.sort[0]
      o ? o.to_time : nil
    end
    
    def poll
      raise! if (will_unacknowledge_at and will_unacknowledge_at.to_time <= MauveTime.now) or
        (will_raise_at and will_raise_at.to_time <= MauveTime.now)
      clear! if will_clear_at && will_clear_at.to_time <= MauveTime.now
    end


    #
    # Tests to see if an alert is raised/acknowledged given a certain set of
    # dates/times.
    #
    #

    def raised?
      !raised_at.nil? and (cleared_at.nil? or raised_at > cleared_at)
    end

    def acknowledged?
      !acknowledged_at.nil?
    end

    #
    # Cleared is just the opposite of raised.
    #
    def cleared?
      !raised?
    end
 
    class << self
    
      #
      # Utility methods to clean/remove html
      #
      def remove_html(txt)
        Sanitize.clean(
          txt.to_s,
          Sanitize::Config::DEFAULT
        )
      end

      def clean_html(txt)
        Sanitize.clean(
          txt.to_s,
         Sanitize::Config::RELAXED.merge({:remove_contents => true})
        )
      end
    
      #
      # Find stuff
      #
      #
      def all_raised
        all(:raised_at.not => nil, :cleared_at => nil) - all_acknowledged
      end

      def all_acknowledged
        all(:acknowledged_at.not => nil)
      end

      def all_cleared
        all(:cleared_at.not => nil) - all_acknowledged
      end

      # Returns a hash of all the :urgent, :normal and :low alerts.
      #
      # @return [Hash] A hash with the relevant alerts per level
      def get_all ()
        hash = Hash.new
        hash[:urgent] = Array.new
        hash[:normal] = Array.new
        hash[:low] = Array.new
        all().each do |iter|
          next if true == iter.cleared?
          hash[AlertGroup.matches(iter)[0].level] << iter
        end
        return hash
      end

      # 
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
     
      #
      # Receive an AlertUpdate buffer from the wire.
      #
      def receive_update(update, reception_time = MauveTime.now)

        update = Proto::AlertUpdate.parse_from_string(update) unless update.kind_of?(Proto::AlertUpdate)

        alerts_updated = []
        
        logger.debug("Alert update received from wire: #{update.inspect.split("\n").join(" ")}")
        
        #
        # Transmission time helps us determine any time offset
        #
        if update.transmission_time and update.transmission_time > 0
          transmission_time = MauveTime.at(update.transmission_time) 
        else
          transmission_time = reception_time
        end

        time_offset = (reception_time - transmission_time).round

        logger.debug("Update received from a host #{time_offset}s behind") if time_offset.abs > 5

        #
        # Make sure there is no HTML in the update source.
        #
        update.source = Alert.remove_html(update.source)

        # Update each alert supplied
        #
        update.alert.each do |alert|
          # 
          # Infer some actions from our pure data structure (hmm, wonder if
          # this belongs in our protobuf-derived class?
          #
          clear_time = alert.clear_time == 0 ? nil : MauveTime.at(alert.clear_time + time_offset)
          raise_time = alert.raise_time == 0 ? nil : MauveTime.at(alert.raise_time + time_offset)

          if raise_time.nil? && clear_time.nil?
            #
            # Make sure that we raise if neither raise nor clear is set
            #
            logger.warn("No clear time or raise time set.  Assuming raised!")

            raise_time = reception_time 
          end

          #
          # Make sure there's no HTML in the ID... paranoia.  The rest of the
          # HTML removal is done elsewhere.
          #
          alert.id = Alert.remove_html(alert.id)
 
          alert_db = first(:alert_id => alert.id, :source => update.source) ||
            new(:alert_id => alert.id, :source => update.source)
          alert_db.update_type = nil
          
          ##
          #
          # Work out if we're raising now, or in the future.
          #
          # Allow a 5s offset in timings.
          #
          if raise_time
            if raise_time <= (reception_time + 5)
              #
              # Don't reset the raised_at time if the alert is already raised.
              # This prevents the raised time constantly changing on alerts
              # that are already raised.
              #
              alert_db.raised_at     = raise_time if alert_db.raised_at.nil?
              alert_db.will_raise_at = nil
            else
              alert_db.raised_at     = nil
              alert_db.will_raise_at = raise_time
            end
          end

          if clear_time
            if clear_time <= (reception_time + 5)
              #
              # Don't reset the cleared_at time (see above for raised_at timings).
              #
              alert_db.cleared_at    = clear_time if alert_db.cleared_at.nil?
              alert_db.will_clear_at = nil
            else
              alert_db.cleared_at    = nil
              alert_db.will_clear_at = clear_time
            end
          end

          #
          # Set the subject
          #
          if alert.subject and !alert.subject.empty?
            alert_db.subject = Alert.remove_html(alert.subject)
          else
            #
            # Use the source, Luke, but only when the subject hasn't already been set.
            #
            alert_db.subject = alert_db.source if alert_db.subject.nil? 
          end

          alert_db.summary = Alert.remove_html(alert.summary) if alert.summary && !alert.summary.empty?

          #
          # The detail can be HTML -- scrub out unwanted parts.
          #
          alert_db.detail = Alert.clean_html(alert.detail)    if alert.detail  && !alert.detail.empty?

          alert_db.importance = alert.importance if alert.importance != 0 

          # 
          # This will probably get overwritten below.
          #
          # alert_db.update_type = "changed" unless alert_db.update_type

          alert_db.updated_at = reception_time 

          if alert_db.raised? 
            #
            # If we're acknowledged, just save.
            #
            if alert_db.acknowledged?
              alert_db.save
            else
              alert_db.raise! 
            end
          else
            alert_db.clear!
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
            alert_db.clear!
          end
        end
       
      end

      def logger
        Log4r::Logger.new("Mauve::Alert")
      end
    end
  end
end

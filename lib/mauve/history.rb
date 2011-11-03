# encoding: UTF-8
require 'mauve/datamapper'
require 'mauve/alert'
require 'log4r'

module Mauve
  # This is the look-up table for Alerts and History to allow one History to
  # have many Alerts and vice-versa
  #
  #
  class AlertHistory
    include DataMapper::Resource

    property :alert_id,   Integer, :key => true
    property :history_id, Integer, :key => true

    belongs_to :alert
    belongs_to :history

    after :destroy, :remove_unreferenced_histories

    # This is a horid migration to allow a move from an older version of Mauve
    # without this table.
    #
    #
    def self.migrate!
      #
      # This copies the alert IDs from the old History table to the new AlertHistories thing, but only if there are no AertHistories 
      # and some Histories
      #
      if AlertHistory.last.nil? and not History.last.nil?
        # 
        # This is horrid. FIXME!
        #
        history_schema = '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "type" VARCHAR(50) DEFAULT \'unknown\' NOT NULL, "event" TEXT DEFAULT \'Nothing set\' NOT NULL, "user" VARCHAR(50) DEFAULT NULL, "created_at" TIMESTAMP NOT NULL'
        history_cols   = 'id, type, event, user, created_at'
        ##
        # Now adjust the Histories table to remove its alert_id col
        #
        ["BEGIN TRANSACTION;",
        "INSERT INTO mauve_alert_histories (alert_id, history_id) SELECT alert_id, id FROM mauve_histories;",
        "CREATE TEMPORARY TABLE mauve_histories_backup( #{history_schema} );",
        "INSERT INTO mauve_histories_backup SELECT #{history_cols} FROM mauve_histories;",
        "DROP TABLE mauve_histories;",
        "CREATE TABLE mauve_histories( #{history_schema} );",
        "INSERT INTO mauve_histories SELECT #{history_cols} FROM mauve_histories_backup;",
        "DROP TABLE mauve_histories_backup;",
        "COMMIT;"].each do |statement|
          repository(:default).adapter.execute(statement)
        end
      end
    end

    private

    # This just removes histories that this AlertHistory used to refer to, if
    # they have no other alerts associated with them
    #
    #
    def remove_unreferenced_histories
      self.history.destroy unless self.history.alerts.count > 0
    end

  end

  # This class keeps a history for Mauve.  One History can relate to zero or
  # more Alerts, allowing notes to be added.
  #
  #
  class History
    include DataMapper::Resource
    
    # so .first always returns the most recent update
    default_scope(:default).update(:order => [:created_at.desc, :id.desc])
   
    #
    # If these properties change.. then the migration above will break horribly. FIXME.
    #
    property :id, Serial
    property :type,  String, :required => true, :default => "unknown", :lazy => false
    property :event, Text, :required => true, :default => "Nothing set", :lazy => false
    property :user, String
    property :created_at, EpochTime, :required => true

    has n, :alerts, :through => :alerthistory

    before :valid?, :do_set_created_at
    before :save,  :do_sanitize_html

    protected

    # This cleans the HTML before saving.
    #
    def do_sanitize_html  
      html_permitted_in = [:event]

      attributes.each do |key, val|
        next if html_permitted_in.include?(key)
        next unless val.is_a?(String)

        attribute_set(key, Alert.remove_html(val))
      end

      html_permitted_in.each do |key|
        val = attribute_get(key)
        next unless val.is_a?(String)
        attribute_set(key, Alert.clean_html(val))
      end
    end

    # Update the created_at time on the object
    #
    def do_set_created_at(context = :default)
      self.created_at = Time.now unless self.created_at.is_a?(Time) 
    end

    public

    # This adds an alert or an array of alerts to the cache of alerts
    # associated with this model.
    #
    # Blasted datamapper not eager-loading my model.
    #
    # @param [Array or Alert] a Array of Alerts or a single Alert
    # @raise ArgumentError If +a+ is not an Array or an Alert
    def add_to_cached_alerts(a)
      @cached_alerts ||= []
      if a.is_a?(Array) and a.all?{|m| m.is_a?(Alert)}
        @cached_alerts += a
      elsif a.is_a?(Alert)
        @cached_alerts << a
      else
        raise ArgumentError, "#{a.inspect} not an Alert"
      end
    end

    # Find all the alerts for this History.  This caches the alerts found.
    # Call #reload to get rid of the cache.
    #
    # @return [Array] Alerts
    def alerts
      @cached_alerts ||= super
    end

    # Reload the object, and clear the cache.
    #
    def reload
      @cached_alerts = nil
      super
    end

    # @return Log4r::Logger
    def logger
      Log4r::Logger.new self.class.to_s
    end

  end

end


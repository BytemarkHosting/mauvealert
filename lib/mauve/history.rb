# encoding: UTF-8
require 'mauve/datamapper'
require 'log4r'

module Mauve
  class AlertHistory
    include DataMapper::Resource

    property :alert_id,   Integer, :key => true
    property :history_id, Integer, :key => true

    belongs_to :alert  
    belongs_to :history 

    def self.migrate!
      #
      # This copies the alert IDs from the old History table to the new AlertHistories thing, but only if there are no AertHistories 
      # and some Histories
      #
      if AlertHistory.last.nil? and not History.last.nil?
        # 
        # This is horrid. FIXME!
        #
        history_schema = '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "type" VARCHAR(50) DEFAULT \'unknown\' NOT NULL, "event" TEXT DEFAULT \'Nothing set\' NOT NULL, "created_at" TIMESTAMP NOT NULL'
        history_cols   = 'id, type, event, created_at'
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

  end

  class History
    include DataMapper::Resource
    
    # so .first always returns the most recent update
    default_scope(:default).update(:order => [:created_at.desc, :id.desc])
   
    #
    # If these properties change.. then the migration above will break horribly. FIXME.
    #
    property :id, Serial
    property :type,  String, :required => true, :default => "unknown"
    property :event, Text, :required => true, :default => "Nothing set"
    property :created_at, Time, :required => true

    has n, :alerts, :through => :alerthistory

    before :valid?, :set_created_at

    def self.migrate!
      ##
      #
      # FIXME this is dire.
      #
      schema = repository(:default).adapter.execute(".schema mauve_histories")



    end

    def set_created_at(context = :default)
      self.created_at = Time.now unless self.created_at.is_a?(Time) or self.created_at.is_a?(DateTime)
    end
    
    def logger
     Log4r::Logger.new self.class.to_s
    end

  end


end


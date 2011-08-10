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
  end

  class History
    include DataMapper::Resource
    
    # so .first always returns the most recent update
    default_scope(:default).update(:order => [:created_at.desc, :id.desc])
    
    property :id, Serial
#    property :alert_id, String, :required  => true
    property :type,  String, :required => true, :default => "unknown"
    property :event, Text, :required => true, :default => "Nothing set"
    property :created_at, DateTime, :required => true

    has n, :alerts, :through => :alerthistory

    before :valid?, :set_created_at

    def set_created_at(context = :default)
      self.created_at = Time.now unless self.created_at.is_a?(Time) or self.created_at.is_a?(DateTime)
    end
    
    def logger
     Log4r::Logger.new self.class.to_s
    end

  end


end


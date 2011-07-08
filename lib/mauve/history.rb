# encoding: UTF-8
require 'mauve/datamapper'
require 'log4r'

module Mauve
  class History
    include DataMapper::Resource
    
    # so .first always returns the most recent update
    default_scope(:default).update(:order => [:created_at.desc, :id.desc])
    
    property :id, Serial
    property :alert_id, Integer, :required  => true
    property :type,  String, :required => true, :default => "unknown"
    property :event, Text, :required => true
    property :created_at, DateTime

    belongs_to :alert
    
    def logger
     Log4r::Logger.new self.class.to_s
    end

  end

end

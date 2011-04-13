# encoding: UTF-8
#
# Bleuurrgggggh!  Bleurrrrrgghh!
#
require 'digest/sha1'
require 'log4r'
require 'thin'
require 'rack'
require 'rack-flash'
require 'rack/handler/webrick'
require 'mauve/auth_bytemark'
require 'mauve/web_interface'
require 'mauve/mauve_thread'

################################################################################
#
# Bodge up thin logging.
# 
module Thin
  module Logging
    
    def log(m=nil)
      # return if Logging.silent?
      logger = Log4r::Logger.new "Mauve::HTTPServer"
      logger.info(m || yield)
    end
    
    def debug(m=nil)
      # return unless Logging.debug?
      logger = Log4r::Logger.new "Mauve::HTTPServer"
      logger.debug(m || yield)
    end
    
    def trace(m=nil)
      return unless Logging.trace?
      logger = Log4r::Logger.new "Mauve::HTTPServer"
      logger.debug(m || yield)
    end
    
    def log_error(e=$!)
      logger = Log4r::Logger.new "Mauve::HTTPServer"
      logger.error(e)
      logger.debug(e.backtrace.join("\n")) 
    end

  end
end

################################################################################
# 
# More logging hacks for Rack
#
# @see http://stackoverflow.com/questions/2239240/use-rackcommonlogger-in-sinatra
#
class RackErrorsProxy

  def initialize(l); @logger = l; end

  def write(msg)
    #@logger.debug "NEXT LOG LINE COURTESY OF: "+caller.join("\n")
    case msg
      when String then @logger.info(msg.chomp)
      when Array then @logger.info(msg.join("\n"))
      else
        @logger.error(msg.inspect)
    end
  end
  
  alias_method :<<, :write
  alias_method :puts, :write
  def flush; end
end



################################################################################
module Mauve

  # 
  # API to control the web server
  #
  class HTTPServer < MauveThread

    include Singleton

    attr_accessor :port, :ip, :document_root
    attr_accessor :session_secret # not used yet
    
    def initialize
      @port = 32761
      @ip = "127.0.0.1"
      @document_root = "."
      @session_secret = rand(2**100).to_s
    end
   
    def main_loop
      @server = ::Thin::Server.new(@ip, @port, Rack::CommonLogger.new(Rack::Chunked.new(Rack::ContentLength.new(WebInterface.new)), RackErrorsProxy.new(@logger)), :signals => false)
      @server.start
    end
    
    def stop
      @server.stop
      super
    end
  end    
end

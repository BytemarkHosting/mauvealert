# encoding: UTF-8
#
# Bleuurrgggggh!  Bleurrrrrgghh!
#
require 'mauve/auth_bytemark'
require 'mauve/web_interface'
require 'mauve/mauve_thread'
require 'digest/sha1'
require 'log4r'
require 'thin'
require 'rack'
require 'rack-flash'
require 'rack/handler/webrick'

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
    attr_accessor :session_secret 
    
    def initialize
      super
      @port = 1288
      @ip = "127.0.0.1"
      @document_root = "/usr/share/mauvealert"
      @session_secret = "%x" % rand(2**100)
    end
   
    def main_loop
      # 
      # Sessions are kept for 8 days.
      #
      @server = ::Thin::Server.new(@ip, @port, Rack::Session::Cookie.new(WebInterface.new, {:key => "mauvealert", :secret => @session_secret, :expire_after => 691200}), :signals => false)
      @server.start
    end
    
    def stop
      @server.stop if @server
      super
    end
  end    
end

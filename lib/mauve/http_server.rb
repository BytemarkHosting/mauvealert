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
require 'ipaddr'
#
# Needed for Lenny version of thin converted by apt-ruby, for some reason.
#
require 'thin_parser'
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

    attr_reader :port, :ip, :document_root, :base_url
    attr_reader :session_secret 
    
    def initialize
      super
      self.port = 1288
      self.ip = "127.0.0.1"
      self.document_root = "./"
      self.session_secret = "%x" % rand(2**100)
    end
   
    def port=(pr)
      raise ArgumentError, "port must be an integer between 0 and #{2**16-1}" unless pr.is_a?(Integer) and pr < 2**16 and pr > 0
      @port = pr
    end
    
    def ip=(i)
      raise ArgumentError, "ip must be a string" unless i.is_a?(String)
      #
      # Use ipaddr to sanitize our IP.
      #
      IPAddr.new(i)
      @ip = i
    end

    def document_root=(d)
      raise ArgumentError, "document_root must be a string" unless d.is_a?(String)
      raise Errno::ENOENT, d unless File.exists?(d)
      raise Errno::ENOTDIR, d unless File.directory?(d)

      @document_root = d
    end

    def base_url=(b)
      raise ArgumentError, "base_url must be a string" unless b.is_a?(String)
      raise ArgumentError, "base_url should start with http:// or https://" unless b =~ /^https?:\/\//
      #
      # Strip off any trailing slash
      #
      @base_url = b.chomp("/")
    end

    def session_secret=(s)
      raise ArgumentError, "session_secret must be a string" unless s.is_a?(String)
      @session_secret = s 
    end

    def main_loop
      # 
      # Sessions are kept for 8 days.
      #
      @server = ::Thin::Server.new(@ip, @port, Rack::Session::Cookie.new(WebInterface.new, {:key => "mauvealert", :secret => @session_secret, :expire_after => 691200}), :signals => false)
      @server.start
    end

    def base_url
      @base_url ||= "http://"+Server.instance.hostname
    end
    
    def stop
      @server.stop if @server
      super
    end
  end    
end

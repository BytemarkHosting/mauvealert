# encoding: UTF-8
#
# Bleuurrgggggh!  Bleurrrrrgghh!
#
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
  #
  # Bodge up thin logging.
  #
  module Logging

    # Log a message at "info" level
    #
    # @param [String] m
    def log(m=nil)
      # return if Logging.silent?
      logger = Log4r::Logger.new "Mauve::HTTPServer"
      logger.info(m || yield)
    end
    
    # Log a message at "debug" level
    #
    # @param [String] m
    def debug(m=nil)
      # return unless Logging.debug?
      logger = Log4r::Logger.new "Mauve::HTTPServer"
      logger.debug(m || yield)
    end
    
    # Log a trace at "debug" level
    #
    # @param [String] m
    def trace(m=nil)
      return unless Logging.trace?
      logger = Log4r::Logger.new "Mauve::HTTPServer"
      logger.debug(m || yield)
    end
    
    # Log a message at "error" level
    #
    # @param [String] e
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

  #
  # Set up the instance
  #
  # @param [Log4r::Logger] l The logger instance.
  #
  def initialize(l); @logger = l; end

  # Log a message at "error" level
  #
  # @param [String or Array] msg
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

  # no-op
  #
  def flush; end
end



################################################################################
module Mauve

  # 
  # The HTTP Server object
  #
  class HTTPServer < MauveThread

    include Singleton

    attr_reader :port, :ip, :document_root, :base_url
    attr_reader :session_secret 
    
    #
    # Initialze the server
    #
    def initialize
      super
      self.port = 1288
      self.ip = "127.0.0.1"
      self.document_root = "./"
      self.session_secret = "%x" % rand(2**100)
    end
   
    # Set the port
    #
    # @param [Intger] pr The port number between 1 and 2**16-1
    # @raise [ArgumentError] If the port is not valid
    def port=(pr)
      raise ArgumentError, "port must be an integer between 1 and #{2**16-1}" unless pr.is_a?(Integer) and pr < 2**16 and pr > 0
      @port = pr
    end
    
    # Set the listening IP address
    #
    # @param [String] i The IP
    def ip=(i)
      raise ArgumentError, "ip must be a string" unless i.is_a?(String)
      #
      # Use ipaddr to sanitize our IP.
      #
      IPAddr.new(i)
      @ip = i
    end

    # Set the document root.
    # @param [String] d The directory where the templates etc are kept.
    # @raise [ArgumentError] If d is not a string
    # @raise [Errno::ENOTDIR] If d does not exist
    # @raise [Errno::ENOTDIR] If d is not a directory
    #
    def document_root=(d)
      raise ArgumentError, "document_root must be a string" unless d.is_a?(String)
      raise Errno::ENOENT, d unless File.exists?(d)
      raise Errno::ENOTDIR, d unless File.directory?(d)

      @document_root = d
    end

    # Set the base URL
    #
    # @param [String] b The base URL, including https?://
    # @raise [ArgumentError] If b is not a string, or https?:// is missing
    def base_url=(b)
      raise ArgumentError, "base_url must be a string" unless b.is_a?(String)
      raise ArgumentError, "base_url should start with http:// or https://" unless b =~ /^https?:\/\//
      #
      # Strip off any trailing slash
      #
      @base_url = b.chomp("/")
    end
    
    # Set the cookie session secret
    #
    # @param [String] s The secret
    # @raise [ArgumentError] if s is not a string
    def session_secret=(s)
      raise ArgumentError, "session_secret must be a string" unless s.is_a?(String)
      @session_secret = s 
    end

    # Return the base_url
    #
    # @return [String]
    def base_url
      @base_url ||= "http://"+Server.instance.hostname
    end
    
    # Stop the server
    #
    def stop
      @server.stop if @server and @server.running?
      super
    end

    # Stop the server, faster than #stop
    #
    def join
      @server.stop! if @server and @server.running?
      super
    end

    private

    #
    # @private This is the main loop to keep the server going.
    #
    def main_loop
      unless @server and @server.running?
        # 
        # Sessions are kept for 8 days.
        #
        @server = ::Thin::Server.new(@ip, @port, Rack::Session::Cookie.new(WebInterface.new, {:key => "mauvealert", :secret => @session_secret, :expire_after => 8.weeks}), :signals => false)
        @server.start
      end
    end
  end    
end

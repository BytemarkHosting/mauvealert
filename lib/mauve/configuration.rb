require 'mauve/source_list'
require 'mauve/people_list'
require 'mauve/mauve_time'

module Mauve

  # Configuration object for Mauve.  This is used as the context in
  # Mauve::ConfigurationBuilder.
  #
  class Configuration

    class << self
      # The current configuration
      # @param  [Mauve::Configuration]
      # @return [Mauve::Configuration]
      attr_accessor :current
    end

    # The Server instance
    # @return [Mauve::Server]
    attr_accessor :server

    # Notification methods
    # @return [Hash]
    attr_reader   :notification_methods

    # People
    # @return [Hash]
    attr_reader   :people
    
    # Alert groups
    # @return [Array]
    attr_reader   :alert_groups

    # People lists
    # @return [Hash]
    attr_reader   :people_lists

    # The source lists
    # @return [Hash]
    attr_reader   :source_lists

    # Various further configuration items
    #
    attr_reader   :bytemark_auth_url, :bytemark_calendar_url, :remote_http_timeout, :remote_https_verify_mode, :failed_login_delay
    attr_reader   :max_acknowledgement_time


    #
    # Set up a base config.
    #
    def initialize
      @server = nil
      @notification_methods = {}
      @people = {}
      @people_lists = {}
      @source_lists = Hash.new{|h,k| h[k] = Mauve::SourceList.new(k)}
      @alert_groups = []

      #
      # Set the auth/calendar URLs
      #
      @bytemark_auth_url     = nil
      @bytemark_calendar_url = nil

      #
      # Set a couple of params for remote HTTP requests.
      #
      @remote_http_timeout = 5
      @remote_https_verify_mode = OpenSSL::SSL::VERIFY_PEER

      #
      # Rate limit login attempts to limit the success of brute-forcing.
      #
      @failed_login_delay = 1

      #
      # Maximum amount of time to acknowledge for
      #
      @max_acknowledgement_time = 15.days
    end

    # Set the calendar URL.
    #
    # @param [String] arg 
    # @return [URI]
    def bytemark_calendar_url=(arg)
      raise ArgumentError, "bytemark_calendar_url must be a string" unless arg.is_a?(String)

      @bytemark_calendar_url = URI.parse(arg)

      #
      # Make sure we get an HTTP URL.
      #
      raise ArgumentError, "bytemark_calendar_url must be an HTTP(S) URL." unless %w(http https).include?(@bytemark_calendar_url.scheme)

      #
      # Set a default request path, if none was given
      #
      @bytemark_calendar_url.normalize!

      @bytemark_calendar_url
    end

    # Set the Bytemark Authentication URL
    #
    # @param [String] arg 
    # @return [URI]
    def bytemark_auth_url=(arg)
      raise ArgumentError, "bytemark_auth_url must be a string" unless arg.is_a?(String)

      @bytemark_auth_url = URI.parse(arg)
      #
      # Make sure we get an HTTP URL.
      #
      raise ArgumentError, "bytemark_auth_url must be an HTTP(S) URL." unless %w(http https).include?(@bytemark_auth_url.scheme)

      #
      # Set a default request path, if none was given
      #
      @bytemark_auth_url.normalize!

      @bytemark_auth_url
    end

    # Sets the timeout when making remote HTTP requests
    #
    # @param [Integer] arg
    # @return [Integer]
    def remote_http_timeout=(arg)
      raise ArgumentError, "remote_http_timeout must be an integer" unless s.is_a?(Integer)
      @remote_http_timeout = arg
    end

    # Sets the SSL verification mode when makeing remote HTTPS requests
    #
    # @param [String] arg must be one of "none" or "peer"
    # @return [Constant]
    def remote_https_verify_mode=(arg)
      @remote_https_verify_mode = case arg
      when "peer"
        OpenSSL::SSL::VERIFY_PEER
      when "none"
        OpenSSL::SSL::VERIFY_NONE
      else
        raise ArgumentError, "remote_https_verify_mode must be either 'peer' or 'none'"
      end
    end

    # Set the delay added following a failed login attempt.
    #
    # @param [Numeric] arg Number of seconds to delay following a failed login attempt
    # @return [Numeric]
    #
    def failed_login_delay=(arg)
      raise ArgumentError, "failed_login_delay must be numeric" unless arg.is_a?(Numeric)
      @failed_login_delay = arg
    end
    
    # Set the maximum amount of time alerts can be ack'd for
    #
    #
    def max_acknowledgement_time=(arg)
      raise ArgumentError, "max_acknowledgement_time must be numeric" unless arg.is_a?(Numeric)
      @max_acknowledgement_time = arg
    end

  end
end

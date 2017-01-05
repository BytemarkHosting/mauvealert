# encoding: UTF-8
require 'digest/sha1'
require 'xmlrpc/client'

#
# This allows poking of the SSL attributes of the http client.
#
module XMLRPC ; class Client ; attr_reader :http ; end ; end

module Mauve

  #
  # Base class for authentication.
  #
  class Authentication

    ORDER = []

    # Authenticate a user.
    #
    # @param [String] login
    # @param [String] password
    #
    # @return [FalseClass] Always returns false.
    def authenticate(login, password)
      raise ArgumentError.new("Login must be a string, not a #{login.class}") if String != login.class
      raise ArgumentError.new("Password must be a string, not a #{password.class}") if String != password.class
      raise ArgumentError.new("Login or/and password is/are empty.") if login.empty? || password.empty?

      false
    end

    # @return [Log4r::Logger]
    def logger
      self.class.logger
    end

    # @return [Log4r::Logger]
    def self.logger
      @logger ||= Log4r::Logger.new(self.to_s)
    end

    # This calls all classes in the ORDER array one by one.  If all classes
    # fail, a 5 second sleep rate-limits authentication attempts.
    #
    # @param [String] login
    # @param [String] password
    #
    # @return [Boolean] Success or failure.
    #
    def self.authenticate(login, password)
      auth_success = ORDER.any? do |klass|
        auth = klass.new

        result = begin
          auth.authenticate(login, password)
        rescue StandardError => ex
          logger.error "#{ex.class}: #{ex.to_s} during #{auth.class} for #{login}"
          logger.debug ex.backtrace.join("\n")
          false
        end

        logger.info "Authenticated #{login} using #{auth.class.to_s}" if true == result

        result
      end

      unless true == result
        logger.info "Authentication for #{login} failed"
        # Rate limit
        sleep Configuration.current.failed_login_delay
      end

      auth_success
    end

  end


  # This is the Bytemark authentication mechanism.
  #
  class AuthBytemark < Authentication

    Mauve::Authentication::ORDER << self

    # Authenticate against the Bytemark server
    #
    # @param [String] login
    # @param [String] password
    #
    # @return [Boolean]
    def authenticate(login, password)
      super

      #
      # Don't bother checking if no auth_url has been set.
      #
      return false unless Configuration.current.bytemark_auth_url.is_a?(URI)

      #
      # Don't bother checking if the person doesn't exist.
      #
      return false unless Mauve::Configuration.current.people.has_key?(login)

      uri     = Configuration.current.bytemark_auth_url
      timeout = Configuration.current.remote_http_timeout
      # host=nil, path=nil, port=nil, proxy_host=nil, proxy_port=nil, user=nil, password=nil, use_ssl=nil, timeout=nil)
      client  = XMLRPC::Client.new(uri.host, uri.path, uri.port, nil, nil, uri.user, uri.password, uri.scheme == "https", timeout)

      #
      # Make sure we verify our peer before attempting login.
      #
      if client.http.use_ssl?
        client.http.ca_path     = "/etc/ssl/certs/" if File.directory?("/etc/ssl/certs")
        client.http.verify_mode = Configuration.current.remote_https_verify_mode
      end

      begin
        proxy = client.proxy("bytemark.auth")
        challenge = proxy.getChallengeForUser(login)
        response = Digest::SHA1.new.update(challenge).update(password).hexdigest
        proxy.login(login, response)
        return true
      rescue XMLRPC::FaultException => fault
        logger.warn "#{self.class} for #{login} failed"
        logger.debug "#{fault.faultCode}: #{fault.faultString}"
        return false
      rescue IOError => ex
        logger.warn "#{ex.class} during auth for #{login} (#{ex.to_s})"
        return false
      end
    end

  end

  # This is the local authentication mechanism, i.e. against the values in the
  # Mauve config file.
  #
  class AuthLocal < Authentication

    Mauve::Authentication::ORDER << self

    # Authenticate against the local configuration
    #
    # @param [String] login
    # @param [String] password
    #
    # @return [Boolean]
    def authenticate(login,password)
      super
      #
      # Don't bother checking if the person doesn't exist.
      #
      return false unless Mauve::Configuration.current.people.has_key?(login)

      #
      # Don't bother checking if no password has been set.
      #
      return false if Mauve::Configuration.current.people[login].password.nil?

      if ( Digest::SHA1.hexdigest(password) == Mauve::Configuration.current.people[login].password )
        return true
      else
        logger.warn "#{self.class} for #{login} failed"
        return false
      end
    end

  end

end

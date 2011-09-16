# encoding: UTF-8
require 'sha1'
require 'xmlrpc/client'
require 'timeout'

module Mauve

  #
  # Base class for authentication.
  #
  class Authentication
    
    ORDER = []

    # Autenticates a user.
    #
    # @param [String] login
    # @param [String] password
    #
    # @return [FalseClass] Always returns false.
    def authenticate(login, password)
      raise ArgumentError.new("Login must be a string, not a #{login.class}") if String != login.class
      raise ArgumentError.new("Password must be a string, not a #{password.class}") if String != password.class
      raise ArgumentError.new("Login or/and password is/are empty.") if login.empty? || password.empty?

      return false unless Mauve::Configuration.current.people.has_key?(login)

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
      result = false

      ORDER.any? do |klass|
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
        sleep 5
      end

      result
    end

  end


  # This is the Bytemark authentication mechansim.
  #
  class AuthBytemark < Authentication

    Mauve::Authentication::ORDER << self

    # Set up the Bytemark authenticator
    #
    # @todo allow configuration of where the server is.
    #
    # @param [String] srv Authentication server name
    # @param [String] port Port overwhich authentication should take place
    #
    # @return [Mauve::AuthBytemark]
    #
    def initialize (srv='auth.bytemark.co.uk', port=443)
      raise ArgumentError.new("Server must be a String, not a #{srv.class}") if String != srv.class
      raise ArgumentError.new("Port must be a Fixnum, not a #{port.class}") if Fixnum != port.class
      @srv = srv
      @port = port
      @timeout = 7

      self
    end

    # Tests to see if a server is alive, alive-o.
    #
    # @deprecated Not really needed.
    #
    # @return [Boolean]
    def ping
      begin
        Timeout.timeout(@timeout) do
          s = TCPSocket.open(@srv, @port)
          s.close()
          return true
        end
      rescue Timeout::Error => ex
        return false
      rescue => ex 
        return false
      end
      return false
    end

    # Authenticate against the Bytemark server
    #
    # @param [String] login
    # @param [String] password
    #
    # @return [Boolean]
    def authenticate(login, password)
      super

      client = XMLRPC::Client.new(@srv,"/",@port,nil,nil,nil,nil,true,@timeout).proxy("bytemark.auth")

      begin
        challenge = client.getChallengeForUser(login)
        response = Digest::SHA1.new.update(challenge).update(password).hexdigest
        client.login(login, response)
        return true
      rescue XMLRPC::FaultException => fault
        logger.warn "Authentication for #{login} failed: #{fault.faultCode}: #{fault.faultString}"
        return false
      rescue IOError => ex
        logger.warn "#{ex.class} during auth for #{login} (#{ex.to_s})"
        return false
      end
    end

  end

  # This is the local authentication mechansim, i.e. against the values in the
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
      Digest::SHA1.hexdigest(password) == Mauve::Configuration.current.people[login].password
    end
  
  end

end

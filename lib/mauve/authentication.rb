# encoding: UTF-8
require 'sha1'
require 'xmlrpc/client'
require 'timeout'

module Mauve

  class Authentication
    
    ORDER = []

    def authenticate(login, password)
      raise ArgumentError.new("Login must be a string, not a #{login.class}") if String != login.class
      raise ArgumentError.new("Password must be a string, not a #{password.class}") if String != password.class
      raise ArgumentError.new("Login or/and password is/are empty.") if login.empty? || password.empty?

      return false unless Mauve::Configuration.current.people.has_key?(login)

      false
    end

    def logger
      self.class.logger
    end

    def self.logger
      @logger ||= Log4r::Logger.new(self.to_s)
    end

    def self.authenticate(login, password)
      result = false

      ORDER.each do |klass|
        auth = klass.new

        result = begin
          auth.authenticate(login, password)
        rescue StandardError => ex
          logger.error "#{ex.class}: #{ex.to_s} during #{auth.class} for #{login}"
          logger.debug ex.backtrace.join("\n")
          false
        end

        if true == result
          logger.info "Authenticated #{login} using #{auth.class.to_s}"
          break
        end
      end

      unless true == result
        logger.info "Authentication for #{login} failed"
        # Rate limit
        sleep 5
      end

      result
    end

  end


  class AuthBytemark < Authentication

    Mauve::Authentication::ORDER << self

    #
    # TODO: allow configuration of where the server is.
    #
    def initialize (srv='auth.bytemark.co.uk', port=443)
      raise ArgumentError.new("Server must be a String, not a #{srv.class}") if String != srv.class
      raise ArgumentError.new("Port must be a Fixnum, not a #{port.class}") if Fixnum != port.class
      @srv = srv
      @port = port
      @timeout = 7
    end

    ## Not really needed.
    def ping ()
      begin
        MauveTimeout.timeout(@timeout) do
          s = TCPSocket.open(@srv, @port)
          s.close()
          return true
        end
      rescue MauveTimeout::Error => ex
        return false
      rescue => ex 
        return false
      end
      return false
    end

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

  class AuthLocal < Authentication

    Mauve::Authentication::ORDER << self

    def authenticate(login,password)
      super
      Digest::SHA1.hexdigest(password) == Mauve::Configuration.current.people[login].password
    end
  
  end

end

# encoding: UTF-8
require 'sha1'
require 'xmlrpc/client'
require 'timeout'

class AuthBytemark 

  def initialize (srv='auth.bytemark.co.uk', port=443)
    raise ArgumentError.new("Server must be a String, not a #{srv.class}") if String != srv.class
    raise ArgumentError.new("Port must be a Fixnum, not a #{port.class}") if Fixnum != port.class
    @srv = srv
    @port = port
    @timeout = 7
    @logger = Log4r::Logger.new(self.class.to_s)
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
    raise ArgumentError.new("Login must be a string, not a #{login.class}") if String != login.class
    raise ArgumentError.new("Password must be a string, not a #{password.class}") if String != password.class
    raise ArgumentError.new("Login or/and password is/are empty.") if login.empty? || password.empty?

    client = XMLRPC::Client.new(@srv,"/",@port,nil,nil,nil,nil,true,@timeout).proxy("bytemark.auth")

    begin
      challenge = client.getChallengeForUser(login)
      response = Digest::SHA1.new.update(challenge).update(password).hexdigest
      client.login(login, response)
      return true
    rescue XMLRPC::FaultException => fault
      Mauve::Server.instance.logger.warn "Fault code is #{fault.faultCode} stating #{fault.faultString}"
      return false
    rescue Exception => ex
      Mauve::Server.instance.logger.warn "Caught #{ex.to_s} whilst trying to loging for #{login}"
      Mauve::Server.instance.logger.debug ex.backtrace.join("\n")
      return false
    end
  end

end

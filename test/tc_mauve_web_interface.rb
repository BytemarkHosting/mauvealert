$:.unshift "../lib"

require 'th_mauve'
require 'th_mauve_resolv'

require 'mauve/alert'
require 'mauve/proto'
require 'mauve/server'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'

require 'rack/test'

ENV['RACK_ENV'] = 'test'

class WebInterfaceTest < Mauve::UnitTest
  include Rack::Test::Methods
  include Mauve

  SESSION_KEY="mauvealert"

  class SessionData
    def initialize(cookies)
      @cookies = cookies
      @data = cookies[WebInterfaceTest::SESSION_KEY]
      if @data
        @data = @data.unpack("m*").first
        @data = Marshal.load(@data)
      else
        @data = {}
      end
    end
    
    def [](key)
      @data[key]
    end
    
    def []=(key, value)
      @data[key] = value
      session_data = Marshal.dump(@data)
      session_data = [session_data].pack("m*")
      @cookies.merge("#{WebInterfaceTest::SESSION_KEY}=#{Rack::Utils.escape(session_data)}", URI.parse("//example.org//"))
      raise "session variable not set" unless @cookies[WebInterfaceTest::SESSION_KEY] == session_data
    end
  end
  
  def session
    SessionData.new(rack_test_session.instance_variable_get(:@rack_mock_session).cookie_jar)
  end

  def setup
    super
    setup_database

    # 
    # BytemarkAuth test users are:
    #
    #   test1: ummVRu7qF
    #   test2: POKvBqLT7
    #
    config =<<EOF
server {
  hostname "localhost"
  database "sqlite::memory:"
  initial_sleep 0

  web_interface {
    document_root "#{File.expand_path(File.join(File.dirname(__FILE__),".."))}"
  }
}

person ("test0") {
  password "#{Digest::SHA1.new.hexdigest("password")}"
  all { true }
}

person ("test1") {
  password "#{Digest::SHA1.new.hexdigest("ummVRu7qF")}"
  all { true }
}

source_list "example_hosts", %w(test-1.example.com test-2.example.com www.example.com www2.example.com)

alert_group("test") {
  includes{ in_source_list?("example_hosts") }

  level LOW

  notify("test1") {
    every 10.minutes
  }

}

alert_group("default") {
  level URGENT

  notify("test1") {
    every 10.minutes
  }
}
EOF

    Configuration.current = ConfigurationBuilder.parse(config)
    Server.instance.setup
  end

  def teardown
    teardown_database
    super
  end

  def app
    Rack::Session::Cookie.new(WebInterface.new, :key => WebInterfaceTest::SESSION_KEY, :secret => "testing-1234")
  end

  def test_log_in
    # Check we get the login page when going to "/" before logging in.
    get '/'
    follow_redirect!  while last_response.redirect?
    assert last_response.ok?
    assert last_response.body.include?("Mauve: Login")
    assert session['__FLASH__'].empty?
    
    # Check we can access this page before logging in.
    get '/alerts'
    assert(session['__FLASH__'].has_key?(:error),"The flash error wasn't set following forbidden access")
    follow_redirect!  while last_response.redirect?
    assert_equal(403, last_response.status, "The HTTP status wasn't 403")
    assert last_response.body.include?("Mauve: Login")
    assert session['__FLASH__'].empty?

    #
    # Try to falsify our login.
    #
    session['username'] = "test1"
    get '/alerts'
    assert(session['__FLASH__'].has_key?(:error),"The flash error wasn't set following forbidden access")
    follow_redirect!  while last_response.redirect?
    assert_equal(403, last_response.status, "The HTTP status wasn't 403")
    assert last_response.body.include?("Mauve: Login")
    assert session['__FLASH__'].empty?

    #
    # OK login with a bad password
    #
    post '/login', :username => 'test1', :password => 'badpassword'
    assert_equal(401, last_response.status, "A bad login did not produce a 401 response")
    assert(last_response.body.include?("Mauve: Login"))
    assert(session['__FLASH__'].has_key?(:error),"The flash error wasn't set")

    #
    # This last login attempt produces two warning messages (one for each auth
    # type), so pop them both off the logger.
    #
    logger_pop ; logger_pop

    post '/login', :username => 'test1', :password => 'ummVRu7qF'
    follow_redirect!  while last_response.redirect?
    assert last_response.body.include?('Mauve: ')

    get '/logout'
    follow_redirect!  while last_response.redirect?
    assert last_response.ok?
  end

  def test_alerts_show_subject
    post '/login', :username => 'test1', :password => 'ummVRu7qF'
    follow_redirect!  while last_response.redirect?
    assert last_response.body.include?('Mauve: ')

    a = Alert.new(:source => "www.example.com", :alert_id => "test_raise!")
    a.raise!

    get '/alerts/raised/subject'
  end

end



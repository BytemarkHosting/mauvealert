$:.unshift "../lib"


require 'th_mauve'
require 'th_mauve_resolv'

require 'mauve/server'
require 'mauve/authentication'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'

require 'webmock'

class TcMauveAuthentication < Mauve::UnitTest
  include Mauve
  include WebMock::API


  def setup
    super
    setup_database
  end

  def teardown
    teardown_database
    super
  end

  def test_default_auth_always_fails
    config=<<EOF
failed_login_delay 0
EOF

    Configuration.current = ConfigurationBuilder.parse(config)
    Server.instance.setup
    assert_equal(false, Authentication.authenticate("test","password"))
    #
    # No warning
    #
    assert_nil(logger_shift)

  end

  def test_local_auth
    config=<<EOF
failed_login_delay 0

person ("test") {
  password "#{Digest::SHA1.new.hexdigest("password")}"
  all { true }
}
EOF

    Configuration.current = ConfigurationBuilder.parse(config)
    Server.instance.setup
    assert(!Authentication.authenticate("test","badpassword"))
    #
    # Should warn that a bad password has been used.
    #
    assert_match(/AuthLocal for test failed/, logger_shift)
    assert(Authentication.authenticate("test","password"))
    #
    # No warnings
    #
    assert_nil(logger_shift)
  end


  def test_local_auth_again
    config=<<EOF
failed_login_delay 0

person ("nopass") { }

person ("test") {
  password "#{Digest::SHA1.new.hexdigest("password")}"
}
EOF

    Configuration.current = ConfigurationBuilder.parse(config)
    Server.instance.setup
    assert(!Authentication.authenticate("nopass","badpassword"))
    logger_shift
    assert(!Authentication.authenticate("test","badpassword"))
    logger_shift
    assert(Authentication.authenticate("test","password"))
  end

  def stub_auth_response(auth_method, success, return_value)
    xml_writer = XMLRPC::XMLWriter::Simple.new
    response_body = XMLRPC::Create.new(xml_writer).methodResponse(success, return_value)
    stub_request(:post, "https://auth.bytemark.co.uk/").
      with(:body => /bytemark\.auth\.#{Regexp.escape(auth_method)}/,:times => 1).
      to_return(:body => response_body,
                :headers => {"Content-Type" => "text/xml"})
  end

  def stub_auth_call(auth_method, return_value)
    stub_auth_response(auth_method, true, return_value)
  end

  def stub_auth_failure(auth_method, failure)
    stub_auth_response(auth_method, false, failure)
  end

  def stub_bad_login
    stub_auth_call("getChallengeForUser", "challengechallengechallenge")
    stub_auth_failure("login", XMLRPC::FaultException.new(91, "Bad login credentials"))
  end

  def stub_good_login
    stub_auth_call("getChallengeForUser", "challengechallengechallenge")
    stub_auth_call("login", "sessionsessionsession")
  end

  def test_bytemark_auth
    #
    # BytemarkAuth test users are:
    #   test1: ummVRu7qF
    #   test2: POKvBqLT7
    #
    config=<<EOF
failed_login_delay 0
bytemark_auth_url "https://auth.bytemark.co.uk/"

person ("test1") { }

person ("test2") {
  password "#{Digest::SHA1.new.hexdigest("password")}"
}

person ("test3") {
  password "#{Digest::SHA1.new.hexdigest("password")}"
}
EOF

    Configuration.current = ConfigurationBuilder.parse(config)
    Server.instance.setup

    #
    # Test to make sure auth can fail
    #
    stub_bad_login
    assert(!Authentication.authenticate("test1","password"))
    #
    # Should issue a warning for just bytemark auth failing, and no more.
    #
    assert_match(/AuthBytemark for test1 failed/, logger_shift)
    assert_nil(logger_shift)

    stub_good_login
    assert(Authentication.authenticate("test1","ummVRu7qF"))
    #
    # Shouldn't issue any warnings.
    #
    assert_nil(logger_shift)

    #
    # Test to make sure that in the event of failure we fall back to local
    # auth, which should also fail in this case.
    #
    stub_bad_login
    assert(!Authentication.authenticate("test2","badpassword"))
    assert_match(/AuthBytemark for test2 failed/, logger_shift)
    assert_match(/AuthLocal for test2 failed/, logger_shift)

    #
    # Test to make sure that in the event of failure we fall back to local
    # auth, which should pass in this case.
    #
    stub_bad_login
    assert(Authentication.authenticate("test2","password"))
    #
    # Should issue a warning for just bytemark auth failing, and no more.
    #
    assert_match(/AuthBytemark for test2 failed/, logger_shift)
    assert_nil(logger_shift)

    #
    # Finally test to make sure local-only still works
    #
    stub_bad_login
    assert(Authentication.authenticate("test3","password"))
    #
    # Should issue a warning for just bytemark auth failing, and no more.
    #
    assert_match(/AuthBytemark for test3 failed/, logger_shift)
    assert_nil(logger_shift)

  end



end

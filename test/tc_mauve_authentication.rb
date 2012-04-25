$:.unshift "../lib"


require 'th_mauve'
require 'th_mauve_resolv'

require 'mauve/server'
require 'mauve/authentication'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'

class TcMauveAuthentication < Mauve::UnitTest 
  include Mauve


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


  def test_local_auth
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
    assert(!Authentication.authenticate("test1","password"))
    # 
    # Should issue a warning for just bytemark auth failing, and no more.
    #
    assert_match(/AuthBytemark for test1 failed/, logger_shift)
    assert_nil(logger_shift)

    assert(Authentication.authenticate("test1","ummVRu7qF"))
    # 
    # Shouldn't issue any warnings.
    #
    assert_nil(logger_shift)
  
    #
    # Test to make sure that in the event of failure we fall back to local
    # auth, which should also fail in this case.
    #
    assert(!Authentication.authenticate("test2","badpassword"))
    assert_match(/AuthBytemark for test2 failed/, logger_shift)
    assert_match(/AuthLocal for test2 failed/, logger_shift)

    #
    # Test to make sure that in the event of failure we fall back to local
    # auth, which should pass in this case.
    #
    assert(Authentication.authenticate("test2","password"))
    # 
    # Should issue a warning for just bytemark auth failing, and no more.
    #
    assert_match(/AuthBytemark for test2 failed/, logger_shift)
    assert_nil(logger_shift)

    #
    # Finally test to make sure local-only still works
    #
    assert(Authentication.authenticate("test3","password"))
    # 
    # Should issue a warning for just bytemark auth failing, and no more.
    #
    assert_match(/AuthBytemark for test3 failed/, logger_shift)
    assert_nil(logger_shift)

  end



end

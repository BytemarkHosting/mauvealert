$:.unshift "../lib/"

require 'th_mauve'
require 'mauve/configuration_builders/person'
require 'pp'

class TcMauveConfigurationBuildersPerson < Mauve::UnitTest

  def test_load
    config=<<EOF
person("test1") {
  all { "this should email on every level" }
  during { "this is the during block" }
  every 300
  email "test1@example.com"
  sms "01234567890"
  xmpp "test1@chat.example.com"
  password "topsekrit"
}
EOF

    x = nil
    assert_nothing_raised { x = Mauve::ConfigurationBuilder.parse(config) }
    assert_equal(1, x.people.length)
    assert_equal(%w(test1), x.people.keys)
    assert_equal(300, x.people["test1"].every)
    assert_equal("test1@example.com", x.people["test1"].email)
    assert_equal("01234567890", x.people["test1"].sms)
    assert_equal("test1@chat.example.com", x.people["test1"].xmpp)
    assert_equal("topsekrit", x.people["test1"].password)

    assert_equal("this is the during block", x.people["test1"].during.call)
    assert_equal("this should email on every level", x.people["test1"].urgent.call)
    assert_equal("this should email on every level", x.people["test1"].normal.call)
    assert_equal("this should email on every level", x.people["test1"].low.call)

  end

end

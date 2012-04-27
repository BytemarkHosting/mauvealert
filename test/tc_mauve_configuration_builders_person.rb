$:.unshift "../lib/"

require 'th_mauve'
require 'mauve/configuration_builders/person'
require 'pp'

class TcMauveConfigurationBuildersPerson < Mauve::UnitTest

  def test_load
    config=<<EOF
person("test1") {
  all { "this should email on every level" }

  email "test1@example.com"
  sms "01234567890"
  xmpp "test1@chat.example.com"

  password "topsekrit"

  notify_when_on_holday!
  notify_when_off_sick!

  notify {
    during { "this is the during block" }
    every 300
  }
}
EOF

    x = nil
    assert_nothing_raised { x = Mauve::ConfigurationBuilder.parse(config) }
    assert_equal(1, x.people.length)
    assert_equal(%w(test1), x.people.keys)

    person = x.people["test1"]
    assert_equal("test1@example.com", person.email)
    assert_equal("01234567890", person.sms)
    assert_equal("test1@chat.example.com", person.xmpp)
    assert_equal("topsekrit", person.password)

#   assert_equal(300, x.people["test1"].every)
#   assert_equal("this is the during block", x.people["test1"].during.call)
#
    assert_equal("this should email on every level", person.urgent.call)
    assert_equal("this should email on every level", person.normal.call)
    assert_equal("this should email on every level", person.low.call)

    assert(person.notify_when_on_holiday)
    assert(person.notify_when_off_sick)
  end

  def test_default_settings 
      config=<<EOF
person("test") 
EOF
    x = nil
    assert_nothing_raised { x = Mauve::ConfigurationBuilder.parse(config) }
    person = x.people["test"]

    assert_equal(nil, person.sms)
    assert_equal(nil, person.email)
    assert_equal(nil, person.xmpp)

    assert_kind_of(Proc, person.low)
    assert_kind_of(Proc, person.normal)
    assert_kind_of(Proc, person.urgent)

    assert_kind_of(Hash, person.notification_thresholds)
    assert_equal(1,person.notification_thresholds.keys.length)
    assert(person.notification_thresholds.all?{|k,v| k.is_a?(Integer) and v.is_a?(Array)})

    assert_kind_of(Array, person.notifications)
    assert_equal(1, person.notifications.length)

    assert(!person.notify_when_on_holiday)
    assert(!person.notify_when_off_sick)
  end

end

$:.unshift "../lib"


require 'th_mauve'
require 'th_mauve_resolv'

require 'mauve/alert'
require 'mauve/proto'
require 'mauve/server'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'

class TcMauveAlert < Mauve::UnitTest 
  include Mauve

  def setup
    super
    setup_database
  end

  def teardown
    teardown_database
    super
  end

  def test_source_list
    config=<<EOF
source_list "test", %w(test-1.example.com)

source_list "has_ipv4", "0.0.0.0/0"

source_list "has_ipv6", "2000::/3"
EOF

    Configuration.current = ConfigurationBuilder.parse(config)

    a = Alert.new
    a.subject = "www.example.com"

    assert( a.in_source_list?("test")     )
    assert_equal( %w(test has_ipv4).sort, a.source_lists.sort )

    a.subject = "www2.example.com"
    assert( a.in_source_list?("has_ipv6") )
    assert_equal( %w(has_ipv6 has_ipv4).sort, a.source_lists.sort )
  end


  def test_summary

    a = Alert.new
    a.summary = "Free swap memory (MB) (memory_swap) is too low"

    assert_match(/memory_swap/, a.summary)

  end


  def test_raise

  config=<<EOF

alert_group("test") {

}

EOF

    Configuration.current = ConfigurationBuilder.parse(config)

    Server.instance.setup

    a= Alert.new(:source => "test-host",
          :alert_id => "test" )    

    a.raise!
  end

  def test_alert_reception
    Server.instance.setup

    update = Proto::AlertUpdate.new
    update.source = "test-host"
    message = Proto::Alert.new
    update.alert << message
    message.id = "test1"
    message.summary = "test summary"
    message.detail  = "test detail"
    message.raise_time = Time.now.to_i
    message.clear_time = Time.now.to_i+5.minutes

    Alert.receive_update(update, Time.now, "127.0.0.1")

    a = Alert.first(:alert_id => 'test1')

    assert(a.raised?)
    assert_equal("test-host",    a.subject)
    assert_equal("test-host",    a.source)
    assert_equal("test detail",  a.detail)
    assert_equal("test summary", a.summary)
    
  end

  def test_alert_ackowledgement
    person = Mauve::Person.new
    person.username = "test-user"

    Server.instance.setup

    Mauve::Configuration.current.people[person.username] = person

    alert = Alert.new(
      :alert_id  => "test-acknowledge",
      :source    => "test",
      :subject   => "test"
    )
    alert.raise!
    assert(alert.raised?)

    alert.acknowledge!(person, Time.now + 3.minutes)
    assert(alert.acknowledged?)

    next_alert = Alert.find_next_with_event
    assert_equal(next_alert.id, alert.id)
    assert_equal(Time.now+3.minutes, next_alert.due_at)    

    Timecop.freeze(next_alert.due_at)

    alert.poll

    #
    # The alert should unacknowledge itself.
    #
    assert(!alert.acknowledged?)


  end

end


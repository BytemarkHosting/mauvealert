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
    @test_config =<<EOF
person ("test") {
  all { true }
}

alert_group("default") {
  level URGENT 

  notify("test") {
    every 10.minutes
  }
}
EOF

  end

  def teardown
    teardown_database
    super
  end

  def test_alert_group

  end


  #
  # This is also the test for in_source_list?
  #
  def test_source_lists
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

  def test_level

  end

  def test_summary
    a = Alert.new
    a.summary = "Free swap memory (MB) (memory_swap) is too low"

    assert_match(/memory_swap/, a.summary)
  end


  def test_raise!
    Server.instance.setup

    a = Alert.new(:source => "test-host", :alert_id => "test_raise!", :subject => "test")

    a.raise!

    assert_equal(Time.now, a.raised_at)

    assert(a.raised?)
    assert(!a.cleared?)
    assert(!a.acknowledged?)
  end

  def test_acknowledge!
    person = Mauve::Person.new("test-user")

    Server.instance.setup

    Mauve::Configuration.current.people[person.username] = person

    alert = Alert.new(
      :alert_id  => "test_acknowledge!",
      :source    => "test",
      :subject   => "test"
    )

    alert.raise!
    logger_pop

    assert(alert.raised?)

    #
    # This acknowledges an alert for 3 mins.
    #
    alert.acknowledge!(person, Time.now + 3.minutes)
    logger_pop

    assert_equal(person.username, alert.acknowledged_by)
    assert_equal(Time.now, alert.acknowledged_at)
    assert_equal(Time.now + 3.minutes, alert.will_unacknowledge_at)
    assert(alert.acknowledged?)


    next_alert = Alert.find_next_with_event
    assert_equal(next_alert.id, alert.id)
    assert_equal(Time.now+3.minutes, next_alert.due_at)    

    Timecop.freeze(Time.now + 3.minutes)


    #
    # The alert should unacknowledge itself.
    #
    alert.poll
    logger_pop

    assert(!alert.acknowledged?)
  end

  def test_unacknowledge!
  end

  def test_clear!
  end

  def test_due_at
  end

  def test_poll
  end

  def test_recieve_update
    Server.instance.setup

    update = Proto::AlertUpdate.new
    update.source = "test-host"
    message = Proto::Alert.new
    update.alert << message
    message.id = "test_recieve_update"
    message.summary = "test summary"
    message.detail  = "test detail"
    message.raise_time = Time.now.to_i
    message.clear_time = Time.now.to_i+5.minutes

    Alert.receive_update(update, Time.now, "127.0.0.1")

    a = Alert.first(:alert_id => 'test_recieve_update')

    assert(a.raised?)
    assert_equal("test-host",    a.subject)
    assert_equal("test-host",    a.source)
    assert_equal("test detail",  a.detail)
    assert_equal("test summary", a.summary)
    
  end

  def test_notify_if_needed
    Configuration.current = ConfigurationBuilder.parse(@test_config)
    Server.instance.setup
    #
    # Notifications should be sent if:
    #
    #  * the alert has changed state (update_type); or
    #  * the alert new and "raised".
    
    alert = Alert.new(
      :alert_id  => "test_notify_if_needed",
      :source    => "test",
      :subject   => "test"
    )

    #
    # Must not notify -- this is a new alert which is not raised.
    #
    alert.clear!
    assert_equal(0, Server.instance.notification_buffer.size, "Notifications sent erroneously on clear.")

    #
    # Now raise.
    #
    alert.raise!
    assert_equal(1, Server.instance.notification_buffer.size, "Wrong number of notifications sent out when new alert raised.")

    #
    # Empty the buffer.
    Server.instance.notification_buffer.pop
    
    Timecop.freeze(Time.now+5)
    alert.raise!
    #
    # Should not re-raise.
    #
    assert_equal(0, Server.instance.notification_buffer.size, "Notification sent erroneously on second raise.")
    
    alert.acknowledge!(Mauve::Configuration.current.people["test"])
    assert_equal(1, Server.instance.notification_buffer.size, "Wrong number of notifications sent erroneously on acknowledge.")
    #
    # Empty the buffer.
    Server.instance.notification_buffer.pop

    alert.subject = "changed subject"
    assert(alert.save)
    assert_equal(0, Server.instance.notification_buffer.size, "Notification sent erroneously on change of subject.")

    alert.clear!
    assert_equal(1, Server.instance.notification_buffer.size, "Wrong number of notifications sent erroneously on clear.")
  end


  #
  # These are more in-depth tests
  #
  def test_no_notification_for_old_alerts
    Configuration.current = ConfigurationBuilder.parse(@test_config)
    Server.instance.setup

    assert_equal(Time.now, Server.instance.started_at)

    Timecop.freeze(Time.now - 10.minutes)
    alert = Alert.new(
      :alert_id  => "test_no_notification_for_old_alerts",
      :source    => "test",
      :subject   => "test",
      :will_raise_at => Time.now + 10.minutes
    )
    alert.clear!

    Timecop.freeze(Time.now + 10.minutes)
    assert_equal(Time.now - 10.minutes, alert.updated_at, "Alert should be last updated before the server instance thinks it started.")

    5.times do 
      assert(Server.instance.in_initial_sleep?,"Server not in initial sleep when it should be.")
      alert.poll
      assert_equal(Server.instance.started_at + Server.instance.initial_sleep, alert.will_raise_at) 
      assert_equal(0, Server.instance.notification_buffer.size, "Notification sent for old alert")
      Timecop.freeze(Time.now + 1.minute)
    end
    #
    # No longer in sleep period.
    #
    assert(!Server.instance.in_initial_sleep?,"Server in initial sleep when it shouldn't be.")
    alert.poll
    assert(alert.raised?)
    assert_equal(1, Server.instance.notification_buffer.size, "Notification sent for old alert")

    #
    # TODO need to do for will_clear_at and will_unacknowledge_at
    #
  end

  def test_heartbeats_during_clock_change

    updates = YAML.load_file(File.join(File.dirname(__FILE__),"bst_to_gmt.yaml"))

    Timecop.freeze(updates.first[1]-20.minutes)
    Configuration.current = ConfigurationBuilder.parse(@test_config)
    Server.instance.setup
    assert_equal(Time.now, Server.instance.started_at)

    updates.each do |update, received_at, source_ip|
      Timecop.freeze(received_at)
      Alert.receive_update(update, received_at, source_ip)
      alert = Alert.first
      assert(alert.cleared?)
      alert.poll
      assert(alert.cleared?)
      assert(0, Server.instance.notification_buffer.length)
    end

  end

end

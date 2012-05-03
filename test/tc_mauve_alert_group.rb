$:.unshift "../lib"

require 'th_mauve'
require 'th_mauve_resolv'
require 'mauve/alert_group'
require 'mauve/server'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'
require 'pp' 

class TcMauveAlertGroup < Mauve::UnitTest 

  include Mauve

  def setup
    super
    setup_database
  end

  def teardown
    teardown_database
    super
  end

  def test_matches_alert

    alert = Alert.new

    alert_group = AlertGroup.new("test")

    alert_group.includes = Proc.new { true }
    assert( alert_group.matches_alert?(alert) )

    alert_group.includes = Proc.new { false }
    assert( !alert_group.matches_alert?(alert) )

    alert_group.includes = Proc.new { summary =~ /Free swap/ }
    alert.summary = "Free swap memory (mem_swap) too low"
    assert( alert_group.matches_alert?(alert) )
    alert.summary = "Free memory (mem_swap) too low"
    assert( ! alert_group.matches_alert?(alert) )

    alert_group.includes = Proc.new{ source == 'supportbot' }
    alert.source = "supportbot"
    assert( alert_group.matches_alert?(alert) )
    alert.source = "support!"
    assert( ! alert_group.matches_alert?(alert) )
    
    alert_group.includes = Proc.new{ /raid/i.match(summary) }
    alert.summary = "RAID failure"
    assert( alert_group.matches_alert?(alert) )
    alert.summary = "Disc failure"
    assert( ! alert_group.matches_alert?(alert) )
  end

  def test_notify
    config=<<EOF
server {
  database "sqlite3::memory:"
  use_notification_buffer false
}

notification_method("email") {
  debug!
  deliver_to_queue []
  disable_normal_delivery!
}

person ("test1") {
  email "test1@example.com"
  all { email }
  notify {
    during { hours_in_day 0 }
  }
}

person ("test2") {
  email "test2@example.com"
  all { email }
  notify {
    during { hours_in_day 0,1 }
  }
}

person ("test3") {
  email "test3@example.com"
  all { email }
  notify {
    during { true }
  }
}

alert_group("default") {
  includes{ true }
  notify("test1") 
  notify("test2") {
    during { hours_in_day 1 }
  }
}
EOF
    Configuration.current = ConfigurationBuilder.parse(config)
    notification_buffer = Configuration.current.notification_methods["email"].deliver_to_queue
    Server.instance.setup

    a = Alert.new(
      :alert_id  => "test",
      :source    => "test",
      :subject   => "test" 
    )

    a.raise!
    assert_equal("test1@example.com", notification_buffer.pop[2])
    assert(notification_buffer.empty?)

    Timecop.freeze(Time.now + 5.minutes)
    a.acknowledge!(Configuration.current.people["test2"], Time.now + 5.minutes)
    assert_equal(2, notification_buffer.length)
    assert_equal(["test1@example.com", "test2@example.com"], notification_buffer.collect{|m| m[2]}.sort)
    notification_buffer.pop until notification_buffer.empty?

    Timecop.freeze(Time.now + 5.minutes)
    a.clear!
    assert_equal(2, notification_buffer.length)
    assert_equal(["test1@example.com", "test2@example.com"], notification_buffer.collect{|m| m[2]}.sort)
    notification_buffer.pop until notification_buffer.empty?

    #
    # If we raise it again, test2 shouldn't get notified.
    #
    Timecop.freeze(Time.now + 5.minutes)
    a.raise!
    assert_equal("test1@example.com", notification_buffer.pop[2])
    assert(notification_buffer.empty?)

    Timecop.freeze(Time.now + 5.minutes)
    a.clear!
    assert_equal("test1@example.com", notification_buffer.pop[2])
    assert(notification_buffer.empty?)

    #
    # Freeze to 1am
    #
    Timecop.freeze(Time.local(2012,5,2,1,0,0))
    
    a.raise!
    assert_equal("test2@example.com", notification_buffer.pop[2])
    assert(notification_buffer.empty?)

    Timecop.freeze(Time.now + 5.minutes)
    a.acknowledge!(Configuration.current.people["test1"], Time.now + 5.minutes)
    assert_equal("test2@example.com", notification_buffer.pop[2])
    assert(notification_buffer.empty?)

    #
    # Test1 shouldn't get notified, even though he ack'd it.
    #
    Timecop.freeze(Time.now + 5.minutes)
    a.clear!
    assert_equal("test2@example.com", notification_buffer.pop[2])
    assert(notification_buffer.empty?)
  end

end





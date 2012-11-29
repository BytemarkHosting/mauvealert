$:.unshift "../lib"

require 'th_mauve'
require 'th_mauve_resolv'
require 'mauve/alert_group'
require 'mauve/server'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'

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
      :subject   => "test",
      :suppress_until => Time.now + 5.minutes 
    )

    a.raise!
    #
    # Should be suppressed.
    #
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

  def test_alert_suppression
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
}

alert_group("default") {
  includes{ true }
  notify("test1")  {
    during{ true }
    every 15.minutes
  }
}
EOF
    Configuration.current = ConfigurationBuilder.parse(config)
    notification_buffer = Configuration.current.notification_methods["email"].deliver_to_queue
    Server.instance.setup

    a = Alert.new(
      :alert_id  => "test",
      :source    => "test",
      :subject   => "test",
      :suppress_until => Time.now + 5.minutes 
    )

    #
    # No notifications should be sent for 5 minutes
    #
    a.raise!

    5.times do
      assert(0,notification_buffer.length)
      Timecop.freeze(Time.now + 1.minutes)
      a.poll
      AlertChanged.all.each{|ac| ac.poll}
    end

    #
    # After 5 minutes a notification should be sent, and a reminder set for 15 minutes afterwards.
    #
    assert(1,notification_buffer.length)
    ac = a.changes.all(:remind_at.not => nil)
    assert_equal(1,ac.length, "Only one reminder should be in place at end of suppression period")
    assert_equal(Time.now+15.minutes, ac.first.remind_at, "Reminder not set for the correct time after suppression")

    #
    # Clear the alert.
    #
    a.clear!
    assert(1, notification_buffer.length)
    ac = a.changes.all(:remind_at.not => nil)
    assert_equal(0,ac.length, "No reminders should be in place after a clear")


    #####
    #
    # This covers a planned maintenance scenario, when an alert is suppressed
    # whilst cleared.  Flapping should not cause any notifications.
    #

    #
    # No notifications should be sent for 15 minutes
    #
    a.suppress_until = Time.now + 15.minutes
    a.clear!

    Timecop.freeze(Time.now + 3.minutes)

    2.times do
      5.times do
        #
        # Raise.  This should not cause any notifications for 10 minutes.
        #
        a.raise!
        assert(0,notification_buffer.length)
        Timecop.freeze(Time.now + 1.minutes)
        a.poll
        AlertChanged.all.each{|ac| ac.poll}
      end

      #
      # This should not raise any alerts, and all reminders should be cleared.
      #
      a.clear!
      assert(0,notification_buffer.length)

      Timecop.freeze(Time.now + 1.minutes)
      a.poll
      AlertChanged.all.each{|ac| ac.poll}

      ac = a.changes.all(:remind_at.not => nil)
      assert_equal(0, ac.length, "Reminder in place at when the raised alert was cleared.")
    end

    # Now re-raise.
    a.raise!
    assert(1,notification_buffer.length)

    ac = a.changes.all(:remind_at.not => nil)
    assert_equal(1,ac.length, "Only one reminder should be in place at end of suppression period")
    assert_equal(Time.now+15.minutes, ac.first.remind_at, "Reminder not set for the correct time after suppression")


  end

end





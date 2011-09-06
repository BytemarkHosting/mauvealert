$:.unshift "../lib"

require 'th_mauve'
require 'mauve/alert'
require 'mauve/alert_changed'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'

class TcMauveAlertChanged < Mauve::UnitTest
  include Mauve

  def setup
    super
    setup_database
  end

  def teardown
    teardown_database
    super
  end

  def test_reminder

    config=<<EOF
person("test_person") {
  all { true }
}

alert_group("test_group") {

  notify("test_person") {
    every 5.minutes
  }

}
EOF

    Configuration.current = ConfigurationBuilder.parse(config)

    Server.instance.setup

    alert = Alert.new(:source => "test", :alert_id => "test_alert", :summary => "test alert")
    alert.raise!

    reminders     = 1
    notifications = 1

    mins = 0
    11.times do
      mins += 1

      assert_equal(notifications, Server.instance.notification_buffer.length)
      assert_equal(reminders, AlertChanged.count)

      Timecop.freeze(Time.now+1.minute)

      if mins % 5 == 0
        notifications += 1
        reminders     += 1
      end

      AlertChanged.all.each{|ac| ac.poll; logger_pop}
    end

    # OK now clear the alert, send one notification and but not an alert_changed.
    alert.clear!
    notifications += 1

    assert_equal(notifications, Server.instance.notification_buffer.length)
    assert_equal(reminders,     AlertChanged.count)

    Timecop.freeze(Time.now + 10.minutes)
    AlertChanged.all.each{|ac| ac.poll}
    #
    # Send NO MORE notifications.
    #
    assert_equal(notifications, Server.instance.notification_buffer.length)
    assert_equal(reminders,   AlertChanged.count)

  end

  def test_only_send_one_alert_on_unacknowledge
    config=<<EOF
person("test_person") {
  all { true }
}

alert_group("test_group") {

  notify("test_person") {
    every 5.minutes
  }

}
EOF

    Configuration.current = ConfigurationBuilder.parse(config)

    Server.instance.setup

    alert = Alert.new(:source => "test", :alert_id => "test_alert", :summary => "test alert")
    alert.raise!
    assert_equal(1,Server.instance.notification_buffer.length, "Wrong no of notifications sent after raise.")
    assert_equal(1,AlertChanged.count, "Wrong no of AlertChangeds created after raise.")

    alert.acknowledge!(Configuration.current.people["test_person"], Time.now + 10.minutes)
    assert_equal(2,Server.instance.notification_buffer.length, "Wrong no of notifications sent after acknowledge.")
    assert_equal(2,AlertChanged.count, "Wrong no of AlertChangeds created after acknowledge.")

    Timecop.freeze(Time.now + 10.minutes)
    AlertChanged.all.each{|ac| ac.poll}
    assert_equal(2,Server.instance.notification_buffer.length, "Extra notifications sent when alertchangeds are polled.")
  
    #
    # OK if we poll the alert now it should be re-raised.
    #
    alert.poll
    assert(!alert.acknowledged?,"Alert not unacknowledged")
    assert(alert.raised?,"Alert not raised following unacknowledgment")
    assert_equal(3,Server.instance.notification_buffer.length, "No re-raise notification sent.")
    #
    # If we poll the AlertChangeds again, no further notification should be sent.
    #
    AlertChanged.all.each{|ac| ac.poll}
    assert_equal(3,Server.instance.notification_buffer.length, "Extra notifications sent when alertchangeds are polled.")
   
  end

end




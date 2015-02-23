$:.unshift "../lib"

require 'th_mauve'
require 'mauve/alert'
require 'mauve/alert_changed'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'
require 'mauve/notifiers'

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
server {
  use_notification_buffer  false
}

notification_method("email") {
  debug!
  deliver_to_queue []
  disable_normal_delivery!
}

person("test_person") {
  email "test_person@example.com"
  all { email }
}

alert_group("test_group") {

  notify("test_person") {
    every 5.minutes
    during { true }
  }

}
EOF


    Configuration.current = ConfigurationBuilder.parse(config)
    notification_buffer = Configuration.current.notification_methods["email"].deliver_to_queue

    Server.instance.setup


    alert = Alert.new(:source => "test", :alert_id => "test_alert", :summary => "test alert")
    alert.raise!

    reminders     = 1
    notifications = 1

    mins = 0
    11.times do
      mins += 1

      #
      # In order to send the notification and stick in the reminder, we need to
      # process the buffer.
      #
      assert_equal(notifications, notification_buffer.length)
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

    assert_equal(notifications, notification_buffer.length)
    assert_equal(reminders,     AlertChanged.count)

    Timecop.freeze(Time.now + 10.minutes)
    AlertChanged.all.each{|ac| ac.poll}
    #
    # Send NO MORE notifications.
    #
    assert_equal(notifications, notification_buffer.length)
    assert_equal(reminders,   AlertChanged.count)

  end

  def test_only_send_one_alert_on_unacknowledge
    config=<<EOF
server {
  use_notification_buffer  false
}

notification_method("email") {
  debug!
  deliver_to_queue []
  disable_normal_delivery!
}

person("test_person") {
  email "test@example.com"
  all { email }
}

alert_group("test_group") {

  notify("test_person") {
    every 5.minutes
    during { true }
  }

}
EOF

    Configuration.current = ConfigurationBuilder.parse(config)
    notification_buffer = Configuration.current.notification_methods["email"].deliver_to_queue

    Server.instance.setup

    alert = Alert.new(:source => "test", :alert_id => "test_alert", :summary => "test alert")
    alert.raise!

    assert_equal(1, notification_buffer.length, "Wrong no of notifications sent after raise.")
    assert_equal(1, AlertChanged.count, "Wrong no of AlertChangeds created after raise.")

    alert.acknowledge!(Configuration.current.people["test_person"], Time.now + 10.minutes)
    assert_equal(2, notification_buffer.length, "Wrong no of notifications sent after raise.")
    assert_equal(2, AlertChanged.count, "Wrong no of AlertChangeds created after acknowledge.")

    #
    # The alert has been acknowledged so send no more reminders.
    #
    Timecop.freeze(Time.now + 10.minutes)
    AlertChanged.all.each{|ac| ac.poll}
    assert_equal(2, notification_buffer.length, "Extra notifications sent when alertchangeds are polled.")

    #
    # OK if we poll the alert now it should be re-raised.
    #
    alert.poll
    assert(!alert.acknowledged?,"Alert not unacknowledged")
    assert(alert.raised?,"Alert not raised following unacknowledgment")
    assert_equal(3, notification_buffer.length, "No re-raise notification sent.")

    #
    # If we poll the AlertChangeds again, no further notification should be sent.
    #
    AlertChanged.all.each{|ac| ac.poll}
    assert_equal(3, notification_buffer.length, "Extra notifications sent when alertchangeds are polled.")
  end

  def test_only_set_one_alert_changed_on_a_reminder_after_multiple_raises_and_clears
    config=<<EOF
server {
  use_notification_buffer  false
}

notification_method("email") {
  debug!
  deliver_to_queue []
  disable_normal_delivery!
}

person("office_chat") {
  email "test@example.com"
  all { email }
}

alert_group("test_group") {

  level NORMAL

  notify("office_chat") {
    every 1.hour
    during { working_hours?  }
  }

}
EOF


    Configuration.current = ConfigurationBuilder.parse(config)
    notification_buffer = Configuration.current.notification_methods["email"].deliver_to_queue

    Server.instance.setup

    alert = Alert.new(:source => "test", :alert_id => "test_alert", :summary => "test alert")

    #
    # Raise and clear the alert multiple times.
    #
    5.times do
      alert.raise!
      Timecop.freeze(Time.now + 15.minutes)
      alert.clear!
      Timecop.freeze(Time.now + 15.minutes)
    end

    #
    # No notification should have been sent, since it is the middle of the night
    #
    assert_equal(0, notification_buffer.length, "No notifications should have been sent.")
    assert(alert.cleared?)

    #
    # Raise one final time.
    #
    alert.raise!
    #
    # Still no alerts should be sent.
    #
    assert_equal(0, notification_buffer.length, "No notifications should have been sent.")
    assert(alert.raised?)

    #
    # Only one AlertChanged should be set now, with a reminder time of 8.30.
    #
    assert_equal(1, AlertChanged.all(:remind_at.not => nil).length, "Too many reminders are due to be sent.")
  end

end




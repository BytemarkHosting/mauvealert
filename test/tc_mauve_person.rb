$:.unshift "../lib"

require 'th_mauve'
require 'mauve/person'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'
require 'pp' 

class TcMauvePerson < Mauve::UnitTest 

  include Mauve

  def setup
    super
    setup_database
  end

  def teardown
    teardown_database
    super
  end

  def test_send_alert
    #
    # Allows us to pick up notifications sent.
    #
    $sent_notifications = []

    config =<<EOF
person ("test") {
  all { $sent_notifications << Time.now ; true }
  suppress_notifications_after( 6 => 60.seconds )
}

alert_group("default") {
  level URGENT

  notify("test") {
    every 10.seconds
  } 
}
EOF
  
    Configuration.current = ConfigurationBuilder.parse(config)
    Server.instance.setup
    person = Configuration.current.people["test"]

    alert = Alert.new(
      :alert_id  => "test",
      :source    => "test",
      :subject   => "test"
    )
    alert.raise!
    assert_equal(false,    person.suppressed?, "Person suppressed before we even begin!")

    start_time = Time.now

    #
    # 6 alerts every 60 seconds.
    #
    [ [0, true, false],
      [5, true, false],
      [10, true, false],
      [15, true, false],
      [20, true, false],
      [25, true, true], # 6th alert -- suppress from now on
      [30, false, true], 
      [35, false, true],
      [40, false, true],
      [60, false, true], # One minute after starting -- should still be suppressed
      [65, false, true],
      [70, false, true],
      [75, false, true],
      [80, false, true],
      [85, true, false], # One minute after the last alert was sent, start sending again.
      [90, true, false]
    ].each do |offset, notification_sent, suppressed|
      # 
      # Advance in to the future!
      #
      Timecop.freeze(start_time + offset)

      person.send_alert(alert.level, alert)

      assert_equal(suppressed,    person.suppressed?, "Suppressed (or not) when it should (or shouldn't) be at #{Time.now}.")

      if notification_sent 
        assert_equal(1, $sent_notifications.length, "Notification not sent when it should have been at #{Time.now}.")
        #
        # Pop the notification off the buffer.
        #
        last_notification_sent_at = $sent_notifications.pop
        assert_equal(Time.now, person.notification_thresholds[60][-1], "Notification thresholds not updated at #{Time.now}.")
      else
        assert_equal(0, $sent_notifications.length, "Notification sent when it should not have been at #{Time.now}.")
      end

      logger_pop
    end

  end

  def test_send_alert_when_only_one_blargh
    #
    # Allows us to pick up notifications sent.
    #
    $sent_notifications = []

    #
    # This configuration is a bit different.  We only want one alert per
    # minute.
    #
    config =<<EOF
person ("test") {
  all { $sent_notifications << Time.now ; true }
  suppress_notifications_after( 1 => 1.minute )
}

alert_group("default") {
  level URGENT

  notify("test") {
    every 10.seconds
  } 
}
EOF
  
    Configuration.current = ConfigurationBuilder.parse(config)
    Server.instance.setup

    person = Configuration.current.people["test"]

    alert = Alert.new(
      :alert_id  => "test",
      :source    => "test",
      :subject   => "test"
    )

    alert.raise!
    assert_equal(false,    person.suppressed?, "Person suppressed before we even begin!")

    start_time = Time.now

    #
    # 1 alerts every 60 seconds.
    #
    [ [0, true,   true],
      [5, false,  true],
      [15, false, true],
      [30, false, true],
      [60, true,  true], # One minute after starting -- should send an alert, but still be suppressed.
      [90, false, true],
      [120, true, true] # Two minutes after starting -- should send an alert, but still be suppressed.
    ].each do |offset, notification_sent, suppressed|
      # 
      # Advance in to the future!
      #
      Timecop.freeze(start_time + offset)

      person.send_alert(alert.level, alert)

      assert_equal(suppressed,    person.should_suppress?, "Suppressed (or not) when it should (or shouldn't) be at #{Time.now}.")

      if notification_sent 
        assert_equal(1, $sent_notifications.length, "Notification not sent when it should have been at #{Time.now}.")
        #
        # Pop the notification off the buffer.
        #
        last_notification_sent_at = $sent_notifications.pop
        assert_equal(Time.now, person.notification_thresholds[60][-1], "Notification thresholds not updated at #{Time.now}.")
      else
        assert_equal(0, $sent_notifications.length, "Notification sent when it should not have been at #{Time.now}.")
      end

      logger_pop
    end

  end

  def test_current_alerts

  end

  def test_is_on_holiday? 

  end
end




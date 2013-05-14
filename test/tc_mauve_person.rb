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
    notification_buffer = []

    config =<<EOF
notification_method("email") {
  debug!
  deliver_to_queue []
  disable_normal_delivery!
}

person ("test") {
  email "test@example.com"
  all { email }
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
    notification_buffer = Configuration.current.notification_methods["email"].deliver_to_queue

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
    [ [0, true],
      [5, true],
      [10, true],
      [15, true],
      [20, true],
      [25, true], # 6th alert -- suppress from now on
      [30, false], 
      [35, false],
      [40, false],
      [60, false], # One minute after starting -- should still be suppressed
      [65, false],
      [70, false],
      [75, false],
      [80, false],
      [85, true], # One minute after the last alert was sent, start sending again.
      [90, true]
    ].each do |offset, notification_sent|
      # 
      # Advance in to the future!
      #
      Timecop.freeze(start_time + offset)
      person.send_alert(alert.level, alert)

      if notification_sent 
        assert_equal(1, notification_buffer.length, "Notification not sent when it should have been at #{Time.now}.")
        #
        # Pop the notification off the buffer.
        #
        notification_buffer.pop
      else
        assert_equal(0, notification_buffer.length, "Notification sent when it should not have been at #{Time.now}.")
      end


      logger_pop
    end

  end

  def test_send_alert_when_only_one_blargh
    #
    # This configuration is a bit different.  We only want one alert per
    # minute.
    #
    config =<<EOF
notification_method("email") {
  debug!
  deliver_to_queue []
  disable_normal_delivery!
}

person ("test") {
  email "test@example.com"
  all { email }
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
    notification_buffer = Configuration.current.notification_methods["email"].deliver_to_queue
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
    [ [0, true ],
      [5, false],
      [15, false],
      [30, false],
      [60, true ], # One minute after starting -- should send an alert.
      [90, false],
      [120, true] # Two minutes after starting -- should send an alert.
    ].each do |offset, notification_sent|
      # 
      # Advance in to the future!
      #
      Timecop.freeze(start_time + offset)

      person.send_alert(alert.level, alert)

      if notification_sent 
        assert_equal(1, notification_buffer.length, "Notification not sent when it should have been at #{Time.now}.")
        #
        # Pop the notification off the buffer.
        #
        notification_buffer.pop
      else
        assert_equal(0, notification_buffer.length, "Notification sent when it should not have been at #{Time.now}.")
      end

      logger_pop
    end

  end

  def test_current_alerts

  end

  def test_is_on_holiday? 

  end
end




$:.unshift "../lib"

require 'mauve/alert'
require 'mauve/alert_changed'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'
require 'th_mauve'

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
  database "sqlite::memory:"
}

person("test_person") {
  all { true }
}

alert_group("test_group") {

  notify("test_person") {
    every 5.minutes
  }

}
EOF

    Mauve::Configuration.current = Mauve::ConfigurationBuilder.parse(config)

    Server.instance.setup

    alert = Mauve::Alert.new(:source => "test", :alert_id => "test_alert", :summary => "test alert")
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


end




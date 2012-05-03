$:.unshift "../lib"

require 'th_mauve'
require 'mauve/people_list'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'
require 'webmock'
require 'pp' 

class TcMauvePeopleList < Mauve::UnitTest 

  include Mauve
  include WebMock::API

  def setup
    super
    setup_database
    WebMock.disable_net_connect!
  end

  def teardown
    WebMock.reset!
    WebMock.allow_net_connect!
    teardown_database
    super
  end

  def test_send_alert
    config =<<EOF
notification_method("email") {
  debug!
  disable_normal_delivery!
  deliver_to_queue []
}

person ("test1") {
  email "test@example.com"
  all { email }
  suppress_notifications_after( 6 => 60.seconds )
}

person ("test2") {
  email "test@example.com"
  all { email }
  suppress_notifications_after( 1 => 1.minute )
}

people_list "testers", %w(test1 test2)

alert_group("default") {
  level URGENT

  notify("testers") {
    every 10.seconds
  } 
}
EOF
    Configuration.current = ConfigurationBuilder.parse(config)
    notification_buffer = Configuration.current.notification_methods["email"].deliver_to_queue

    Server.instance.setup
    people_list = Configuration.current.people["testers"]

    alert = Alert.new(
      :alert_id  => "test",
      :source    => "test",
      :subject   => "test"
    )
    alert.raise!
#    assert_equal(false,    .suppressed?, "Person suppressed before we even begin!")

    start_time = Time.now

    #
    # 6 alerts every 60 seconds.
    #
    [ [0, true, true],
      [5, true, false],
      [10, true, false],
      [15, true, false],
      [20, true, false],
      [25, true, false], # 6th alert -- suppress from now on
      [30, false, false], 
      [35, false, false],
      [40, false, false],
      [60, false, true], # One minute after starting -- should still be suppressed
      [65, false, false],
      [70, false, false],
      [75, false, false],
      [80, false, false],
      [85, true, false], # One minute after the last alert was sent, start sending again.
      [90, true, false]
    ].each do |offset, test1sent, test2sent|
      # 
      # Advance in to the future!
      #
      Timecop.freeze(start_time + offset)

      people_list.people.each{|person| person.send_alert(alert.level, alert) }


      if test1sent or test2sent
        n_notifications = (test2sent ? 1 : 0) + (test1sent ? 1 : 0)
        assert_equal(n_notifications, notification_buffer.length, "Notification not sent when it should have been at #{Time.now}.")
        #
        # Pop the notification off the buffer.
        #
        n_notifications.times{ notification_buffer.pop }
#        assert_equal(Time.now, person.notification_thresholds[60][-1], "Notification thresholds not updated at #{Time.now}.")
      else
        assert_equal(0, notification_buffer.length, "Notification sent when it should not have been at #{Time.now}.")
      end


      logger_pop
    end

  end
  
  def test_dynamic_people_list
    config =<<EOF
bytemark_calendar_url "http://localhost"

person "test1"
person "test2"

#
# This should oscillate between test1 and test2.
#
people_list "testers", calendar("support_shift")

EOF
    Configuration.current = ConfigurationBuilder.parse(config)

    #
    # Stub HTTP requests to return test1 now, and tes2 later.
    #
    stub_request(:get, "http://localhost/api/attendees/support_shift/2011-08-01T00:00:00").
      to_return(:status => 200, :body => YAML.dump(%w(test1)))

    stub_request(:get, "http://localhost/api/attendees/support_shift/2011-08-01T00:05:00").
      to_return(:status => 200, :body => YAML.dump(%w(test2)))
    
    people_list = Configuration.current.people["testers"]
    assert_equal([Configuration.current.people["test1"]], people_list.people)
    assert_equal([Configuration.current.people["test2"]], people_list.people(Time.now + 5.minutes))
  end

end

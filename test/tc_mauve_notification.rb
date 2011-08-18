$:.unshift "../lib"

require 'th_mauve'
require 'mauve/alert'
require 'mauve/notification'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'
require 'mauve/mauve_time'

class TcMauveDuringRunner < Mauve::UnitTest 

  include Mauve

  def setup
    super
    setup_database
  end

  def teardown
    teardown_database
    super
  end

  def test_initialize

    alert = Alert.new
    time = Time.now
    during = Proc.new { false }

    dr = DuringRunner.new(time, alert, &during)

    assert_equal(dr.alert, alert)
    assert_equal(dr.time, time)
    assert_equal(dr.during, during)
    
  end

  def test_now?
    alert = Alert.new
    time = Time.now
    during = Proc.new { @test_time }

    dr = DuringRunner.new(time, alert, &during)
    
    assert_equal(time, dr.now?)
    assert_equal(time+3600, dr.now?(time+3600))
    assert_equal(time, dr.time)
  end

  def test_find_next
    #
    # An alert is supposed to remind someone every six hours during working
    # hours, and it is raised outside working hours.  Assuming it is still
    # raised when working hours start, when should the first reminder get sent?
    #
    # (a) As soon as working hours commence.
    # (b) At some point in the first six hours of working hours.
    # (c) After six working hours.
    #
    # (12:38:19) Nick: a)
   
    #
    # This should give us midnight last sunday night.
    #
    now = Time.now 

    #
    # first working hour on Monday
    workday_morning   = now.in_x_hours(0,"working")

    assert(workday_morning != now, "booo")

    #
    # This should alert at exactly first thing on Monday morning.
    #
    dr = DuringRunner.new(now, nil){ working_hours? }
    assert_equal(dr.find_next(6.hours), workday_morning)
    
    #
    # This should alert six hours later than the last one.
    #
    dr = DuringRunner.new(workday_morning, nil){ working_hours? }
    assert_equal(dr.find_next(6.hours), workday_morning + 6.hours)

    #
    # Now assuming the working day is not 12 hours long, if we progress to 6
    # hours in the future then the next alert should be first thing on Tuesday.
    #
    dr = DuringRunner.new(workday_morning + 6.hours, nil){ working_hours? }
    tuesday_morning = workday_morning+24.hours
    assert_equal(dr.find_next(6.hours), tuesday_morning)

    #
    # If an alert is too far in the future (a week) return nil.
    #
    dr = DuringRunner.new(workday_morning, nil){ @test_time > (@time + 12.days) }
    assert_nil(dr.find_next)
  end

  def test_hours_in_day
  end

  def test_days_in_week
  end

  def test_unacknowledged
  end

end

class TcMauveNotification < Mauve::UnitTest 

  include Mauve
  
  def setup
    super
    setup_database
  end

  def teardown
    teardown_database
    super
  end

  def test_notify
    t = Time.now

    config=<<EOF
person ("test1") {
  all { true }
}

person ("test2") {
  all { true }
}

person ("test3") {
  all { true }
}

people_list "testers", %w(
  test1
  test2
)

alert_group("default") {
  level URGENT 

  notify("test1") {
    every 10.minutes
  }
  
  notify("test1") {
    every 15.minutes
  }

  notify("test2") {
    during { hours_in_day 1..23   }
    every 10.minutes
  }
  
  notify("test3") {
    during { unacknowledged( 2.hours ) }
    every 10.minutes
  }

}
EOF

    Configuration.current = ConfigurationBuilder.parse(config) 
    Server.instance.setup
    alert = Alert.new(
      :alert_id  => "test", 
      :source    => "test",
      :subject   => "test"
    )
    alert.raise!

    assert_equal(1, Alert.count, "Wrong number of alerts saved")

    #
    # Although there are four clauses above for notifications, test1 should be
    # alerted in 10 minutes time, and the 15 minutes clause is ignored, since
    # 10 minutes is sooner.
    #
    assert_equal(3, AlertChanged.count, "Wrong number of reminders inserted")

    #
    # Also make sure that only 1 notification has been sent..
    #
    assert_equal(1, Server.instance.notification_buffer.size, "Wrong number of notifications sent")

    reminder_times = {
      "test1" => t + 10.minutes,
      "test2" => t + 1.hour,
      "test3" => t + 2.hours
    }

    AlertChanged.all.each do |a|
      assert_equal("urgent", a.level, "Level is wrong for #{a.person}")
      assert_equal("raised", a.update_type, "Update type is wrong for #{a.person}")
      assert_equal(reminder_times[a.person], a.remind_at,"reminder time is wrong for #{a.person}")
    end

  end

end

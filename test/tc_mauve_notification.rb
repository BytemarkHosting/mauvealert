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
    during = Proc.new { Time.now == @test_time }

    dr = DuringRunner.new(time, alert, &during)
    
    assert_equal(true, dr.now?)
    assert_equal(false, dr.now?(time+3600))
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


  def test_x_in_list_of_y
    dr = DuringRunner.new(Time.now)
    [
      [[0,1,3,4], 2, false],
      [[0,2,4,6], 2, true],
      [[0..1,3..6],2, false],
      [[0..2, 4,5],2, true],
      [[0,1..3], 2, true],
    ].each do |y,x,result|
      assert_equal(result, dr.send(:x_in_list_of_y, x,y))
    end
  end

  def test_hours_in_day
    t = Time.gm(2010,1,2,3,4,5)
    # => Sat Jan 02 03:04:05 UTC 2010
    dr = DuringRunner.new(t)
    [
      [[0,1,3,4], true],
      [[0,2,4,6], false],
      [[[0,1,3],4], true],
      [[[0,2,4],6], false],
      [[0..1,3..6], true],
      [[0..2, 4,5], false],
      [[0,1..3], true],
      [[4..12], false]
    ].each do |hours, result|
      assert_equal(result, dr.send(:hours_in_day, hours))
    end
  end

  def test_days_in_week
    t = Time.gm(2010,1,2,3,4,5)
    # => Sat Jan 02 03:04:05 UTC 2010
    dr = DuringRunner.new(t)
    [
      [[0,1,3,4], false],
      [[0,2,4,6], true],
      [[[0,1,3],4], false],
      [[[0,2,4],6], true],
      [[0..1,3..6], true],
      [[0..2, 4,5], false],
      [[0,1..3], false],
      [[4..6], true]
    ].each do |days, result|
      assert_equal(result, dr.send(:days_in_week, days), "#{t.wday} in #{days.join(", ")}")
    end
  end

  def test_unacknowledged
    Server.instance.setup
    alert = Alert.new(
      :alert_id  => "test", 
      :source    => "test",
      :subject   => "test"
    )
    alert.raise!

    Timecop.freeze(Time.now+1.hour)

    dr = DuringRunner.new(Time.now, alert)

    assert(!dr.send(:unacknowledged, 2.hours))
    assert(dr.send(:unacknowledged, 1.hour))
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
notification_method("email") {
  debug!
  deliver_to_queue []
  disable_normal_delivery!
}

person ("test1") {
  email "test1@example.com"
  all { email }
}

person ("test2") {
  email "test2@example.com"
  all { email }
}

person ("test3") {
  email "test3@example.com"
  all { email }
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
  
  notify("testers") {
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
    notification_buffer = Configuration.current.notification_methods["email"].deliver_to_queue

    Server.instance.setup
    alert = Alert.new(
      :alert_id  => "test", 
      :source    => "test",
      :subject   => "test"
    )
    alert.raise!

    assert_equal(1, Alert.count, "Wrong number of alerts saved")
    
    #
    # Also make sure that only 2 notifications has been sent..
    #
    assert_nothing_raised{ Notifier.instance.__send__(:main_loop) }
    assert_equal(2, notification_buffer.size, "Wrong number of notifications sent")

    #
    # Although there are four clauses above for notifications, test1 should be
    # alerted in 10 minutes time, and the 15 minutes clause is ignored, since
    # 10 minutes is sooner.
    #
    assert_equal(1, AlertChanged.count, "Wrong number of reminders inserted")

    a = AlertChanged.first 
    assert_equal("urgent", a.level, "Level is wrong for #{a.person}")
    assert_equal("raised", a.update_type, "Update type is wrong for #{a.person}")
    assert_equal(Time.now + 10.minutes, a.remind_at,"reminder time is wrong for #{a.person}")

    #
    # OK now roll the clock forward 10 minutes
    # TODO

  end


  #
  # Makes sure a reminder is set at the start of the notify clause.
  #  
  def test_reminder_is_set_at_start_of_during

    config=<<EOF
person ("test1") {
  all { true }
}

person ("test2") {
  all { true }
}

alert_group("default") {
  level URGENT
  notify("test1") {
    every 10.minutes
  } 

  notify("test2") {
    every 10.minutes
    during { hours_in_day 8..10 }
  }

}
EOF

    #
    # Wind forward until 7.55am
    #
    Timecop.freeze(Time.now + 7.hours + 55.minutes)

    Configuration.current = ConfigurationBuilder.parse(config)
    Server.instance.setup
    alert = Alert.new(
      :alert_id  => "test",
      :source    => "test",
      :subject   => "test"
    )
    alert.raise!

    assert_nothing_raised{ Notifier.instance.__send__(:main_loop) }

    assert_equal(1, Alert.count, "Wrong number of alerts saved")
    assert_equal(1, AlertChanged.count, "Wrong number of reminders inserted")

    a = AlertChanged.first
    assert_equal("urgent", a.level, "Level is wrong for #{a.person}")
    assert_equal("raised", a.update_type, "Update type is wrong for #{a.person}")
    assert_equal(Time.now + 5.minutes, a.remind_at,"reminder time is wrong for #{a.person}")

  end


  #
  # Test to make sure that if a bondary is crossed, then the during clauses all
  # work. 
  #  
  def test_no_race_conditions_in_during

    config=<<EOF
notification_method("email") {
  debug!
  deliver_to_queue []
  disable_normal_delivery!
}

person ("test1") {
  email "test1@example.com"
  all { email }
}

person ("test2") {
  email "test1@example.com"
  all { email }
}

alert_group("default") {
  level URGENT
  notify("test1") {
    every 0
    during { sleep 2 ; hours_in_day 1..7 }
  } 

  notify("test2") {
    every 0 
    during { hours_in_day 8..10 }
  }

}
EOF

    #
    # Wind forward until 7:59:59am
    #
    Configuration.current = ConfigurationBuilder.parse(config)
    notification_buffer = Configuration.current.notification_methods["email"].deliver_to_queue

    Server.instance.setup
    
    alert = Alert.new(
      :alert_id  => "test",
      :source    => "test",
      :subject   => "test"
    )

    Timecop.travel(Time.now + 7.hours + 59.minutes + 59.seconds)
    alert.raise!

    assert_nothing_raised{ Notifier.instance.__send__(:main_loop) }

    assert_equal(1, notification_buffer.size, "Wrong number of notifications sent")
  end


end

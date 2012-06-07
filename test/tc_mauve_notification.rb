$:.unshift "../lib"

require 'th_mauve'
require 'mauve/mauve_time'
require 'mauve/alert'
require 'mauve/notification'
require 'mauve/server'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'
require 'webmock'

class TcMauveDuringRunner < Mauve::UnitTest 

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
      [3..3.5, true],
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

  def test_working_hours
    config=<<EOF
working_hours 0..2.5
EOF

    Configuration.current = ConfigurationBuilder.parse(config)

  end

  def test_no_one_in
    config=<<EOF
person "test1"
person "test2"

people_list "empty", %w( )
people_list "not empty", %w(test1 test2)
EOF

    Configuration.current = ConfigurationBuilder.parse(config)

    dr = DuringRunner.new(Time.now)

    assert(dr.send(:no_one_in, "non-existent list"))
    assert(dr.send(:no_one_in, "empty"))
    #
    # We expect an empty list to generate a warning.
    #
    logger_pop
    assert(!dr.send(:no_one_in, "not empty"))
  end

  def test_no_one_in_with_calendar
    config=<<EOF
bytemark_calendar_url "http://localhost"
person "test1"
person "test2"

people_list "support", calendar("support_shift")
EOF

    Configuration.current = ConfigurationBuilder.parse(config)

    #
#
#    5.times.each do |hr|
#    end


    dr = DuringRunner.new(Time.now, nil) {
      no_one_in("support")
    }
    
    #
    # Stub the URL
    #
    url ="http://localhost/api/attendees/support_shift/#{Time.now.strftime("%Y-%m-%dT%H:%M:00")}"
    stub_request(:get, url).to_return(:status => 200, :body => YAML.dump(%w(test1 test2)))
    
    assert(!dr.now?)

    #
    # Advance by 5 minutes, and try again -- we should get the same answer,
    # since the DuringRunner's time does not change.
    #
    Timecop.freeze(Time.now + 5.minutes)
    assert(!dr.now?)
    #
    # Roll back 5 minutes.
    #
    Timecop.freeze(Time.now - 5.minutes)
  
    #
    # That last round of requests should only have hit the midnight URL once.
    #
    assert_requested(:get, url, :times => 1)
    WebMock.reset!

    #
    # Set up a new runner.
    #
    dr = DuringRunner.new(Time.now, nil) {
      no_one_in("support")
    }

    #
    # This time our URL returns an empty list.
    #
    stub_request(:get, url).to_return(:status => 200, :body => YAML.dump([]))
    assert(dr.now?)
    
    #
    # We expect a warning about an empty list.
    #
    logger_pop

    #
    # This should make a new request to the 00:05 URL
    #
    assert_requested(:get, url, :times => 1)
    WebMock.reset!

    #
    # Set up a new runner.
    #
    dr = DuringRunner.new(Time.now, nil) {
      no_one_in("support")
    }

    #
    # Set up our stubs.  The first is to catch any iterations done by find_next.
    #
    stub_request(:get, /http:\/\/localhost\/api\/attendees\/support_shift\/(.*)/).
      to_return do |request| 
        t = Time.parse(request.uri.path.split("/").last)
        if t >= Time.now and t < Time.now + 5.minutes
          {:status => 200, :body => YAML.dump(%w(test1 test2))}
        else
          {:status => 200, :body => YAML.dump([])}
        end
      end

    assert(!dr.now?)
    assert_equal(Time.now + 5.minutes, dr.find_next(0))
    logger_pop
    logger_pop

    #
    # This should make 5 requests, one in an hours time (the initial step) +
    #
    WebMock::RequestRegistry.instance.requested_signatures.each do |request, count|
      assert_equal(1, count, "URI #{request.uri.to_s} requested more than once during find_next()")
    end

  end

  def test_bank_holiday
config=<<EOF
bytemark_calendar_url "http://localhost"
EOF

    Configuration.current = ConfigurationBuilder.parse(config)
    Server.instance.setup

    stub_request(:get, "http://localhost/api/bank_holidays/2011-08-01").
      to_return(:status => 200, :body => YAML.dump([]))

    dr = DuringRunner.new(Time.now)
    assert(!dr.send(:bank_holiday?))

    #
    # Add today as a bank hol.
    #
    # time.bank_holidays << Date.new(Time.now.year, Time.now.month, Time.now.day)
   
    Timecop.freeze(Time.now + 24.hours)
    stub_request(:get, "http://localhost/api/bank_holidays/2011-08-02").
      to_return(:status => 200, :body => YAML.dump([Date.new(2011,8,2)]))

    dr = DuringRunner.new(Time.now)
    assert(dr.send(:bank_holiday?))
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
server {
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
    during { true }
    every 10.minutes
  }
  
  notify("testers") {
    during { true }
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
server {
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

person ("test2") {
  email "test2@example.com"
  all { email }
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
server {
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

    assert_equal(1, notification_buffer.size, "Wrong number of notifications sent")
  end


  def test_individual_notification_preferences
    config=<<EOF
server {
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
    every 300
    during { hours_in_day(0) }
  }
}

person ("test2") {
  email "test2@example.com"
  all { email }
  notify {
    every 300
    during { hours_in_day(1) }
  }
}

people_list("testers", %w(test1 test2)) {
  notify {
    every 150
    during { hours_in_day(2) }
  }
}

alert_group("test") {
  level URGENT

  notify("test1") 
  notify("test2")
  notify("testers")

  notify("testers") {
    every 60
    during { hours_in_day (3) }
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
    
    # At midnight just test1
    # At 1am just test2
    # At 2am, both test1 and test2 (via testers)
    # At 3am both test1 and test2 (via testers clause with during)
    # At 4am no-one 

    [
      [0, %w(test1)],
      [1, %w(test2)],
      [2, %w(test1 test2)],
      [3, %w(test1 test2)],
      [4, []]
    ].each do |hour, people|

      assert_equal(hour, Time.now.hour)
      alert.raise!
      assert_equal(people.length, notification_buffer.size, "Wrong number of notifications sent after a raise at #{hour} am")
      sent = []
      sent << notification_buffer.pop while !notification_buffer.empty?
      assert_equal(people.collect{|u| "#{u}@example.com"}.sort, sent.collect{|n| n[2]}.sort)

      alert.clear!
      assert_equal(people.length, notification_buffer.size, "Wrong number of notifications sent after a clear at #{hour} am")
      sent = []
      sent << notification_buffer.pop while !notification_buffer.empty?
      assert_equal(people.collect{|u| "#{u}@example.com"}.sort, sent.collect{|n| n[2]}.sort)
      
      #
      # Wind the clock forward for the next round of tests.
      #
      Timecop.freeze(Time.now+1.hours)
    end
  end

  def test_individual_notification_preferences_part_deux
    config=<<EOF
server {
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
    every 300
    during { hours_in_day(0) }
  }
}

person ("test2") {
  email "test2@example.com"
  all { email }
  notify {
    every 300
    during { hours_in_day(1) }
  }
}

people_list("testers", %w(test1 test2)) 

alert_group("test") {
  level URGENT

  notify("testers")

  notify("testers") {
    every 60
    during { hours_in_day (2) }
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
 
    #
    # At midnight just test1 should be notified.
    # At 1am, just test2
    # At 2am both test1 and test2 
 
    [
      [0, %w(test1)],
      [1, %w(test2)],
      [2, %w(test1 test2)]
    ].each do |hour, people|

      assert_equal(hour, Time.now.hour)
      alert.raise!
      assert_equal(people.length, notification_buffer.size, "Wrong number of notifications sent after a raise at #{hour} am")
      sent = []
      sent << notification_buffer.pop while !notification_buffer.empty?
      assert_equal(people.collect{|u| "#{u}@example.com"}.sort, sent.collect{|n| n[2]}.sort)

      alert.clear!
      assert_equal(people.length, notification_buffer.size, "Wrong number of notifications sent after a clear at #{hour} am")
      sent = []
      sent << notification_buffer.pop while !notification_buffer.empty?
      assert_equal(people.collect{|u| "#{u}@example.com"}.sort, sent.collect{|n| n[2]}.sort)
      
      #
      # Wind the clock forward for the next round of tests.
      #
      Timecop.freeze(Time.now+1.hours)
    end

  end

  def test_notify_array_of_usernames
    config=<<EOF
server {
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
    every 100
    during { hours_in_day(1) }
  }
}

person ("test2") {
  email "test2@example.com"
  all { email }
  notify {
    every 200
    during { hours_in_day(2) }
  }
}

person ("test3") {
  email "test3@example.com"
  all { email }
  notify {
    every 300
    during { hours_in_day(3) }
  }
}

people_list("testers1", %w(test1 test2)) 

people_list("testers2", "testers1", "test3") {
  notify {
    every 500 
    during { hours_in_day(4) }
  }
}

alert_group("test") {
  level URGENT

  includes { source == "test" }

  notify("test1", "testers1", "testers2")
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
    assert_equal("test", alert.alert_group.name)

    # At midnight no-one should be alerted
    # At 1am just test1 should be alerted
    # At 2am just test2 should be alerted (via the testers1 group)
    # At 3am no-one should be alerted
    # At 4am test1, test2, and test3 should all be alerted (via the testers2 group)
 
    [
      [0, []],
      [1, %w(test1)],
      [2, %w(test2)],
      [3, []],
      [4, %w(test1 test2 test3)]
    ].each do |hour, people|

      assert_equal(hour, Time.now.hour)
      alert.raise!
      assert_equal(people.length, notification_buffer.size, "Wrong number of notifications sent after a raise at #{hour} am")
      sent = []
      sent << notification_buffer.pop while !notification_buffer.empty?
      assert_equal(people.collect{|u| "#{u}@example.com"}.sort, sent.collect{|n| n[2]}.sort)

      alert.clear!
      assert_equal(people.length, notification_buffer.size, "Wrong number of notifications sent after a clear at #{hour} am")
      sent = []
      sent << notification_buffer.pop while !notification_buffer.empty?
      assert_equal(people.collect{|u| "#{u}@example.com"}.sort, sent.collect{|n| n[2]}.sort)
      
      #
      # Wind the clock forward for the next round of tests.
      #
      Timecop.freeze(Time.now+1.hours)
    end

  end
end

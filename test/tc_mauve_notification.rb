$:.unshift "../lib"

require 'test/unit'
require 'mauve/alert'
require 'mauve/notification'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'
require 'mauve/mauve_time'
require 'th_mauve_resolv'
require 'th_mauve_time'
require 'th_logger'
require 'pp' 



class TcMauveDuringRunner < Test::Unit::TestCase 

  def test_initialize

    alert = Mauve::Alert.new
    time = Time.now
    during = Proc.new { false }

    dr = Mauve::DuringRunner.new(time, alert, &during)

    assert_equal(dr.alert, alert)
    assert_equal(dr.time, time)
    assert_equal(dr.during, during)
    
  end

  def test_now?
    alert = Mauve::Alert.new
    time = Time.now
    during = Proc.new { @test_time }

    dr = Mauve::DuringRunner.new(time, alert, &during)
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
    midnight_sunday = now  - (now.hour.hours + now.min.minutes + now.sec.seconds + now.wday.days)

    #
    # first working hour on Monday
    monday_morning   = midnight_sunday.in_x_hours(0,"working")

    #
    # This should alert at exactly first thing on Monday morning.
    #
    dr = Mauve::DuringRunner.new(midnight_sunday, nil){ working_hours? }
    assert_equal(dr.find_next(6.hours), monday_morning)
    
    #
    # This should alert six hours later than the last one.
    #
    dr = Mauve::DuringRunner.new(monday_morning, nil){ working_hours? }
    assert_equal(dr.find_next(6.hours), monday_morning + 6.hours)

    #
    # Now assuming the working day is not 12 hours long, if we progress to 6
    # hours in the future then the next alert should be first thing on Tuesday.
    #
    dr = Mauve::DuringRunner.new(monday_morning + 6.hours, nil){ working_hours? }
    tuesday_morning = monday_morning+24.hours
    assert_equal(dr.find_next(6.hours), tuesday_morning)

    #
    # If an alert is too far in the future (a week) return nil.
    #
    dr = Mauve::DuringRunner.new(monday_morning, nil){ @test_time > (@time + 12.days) }
    assert_nil(dr.find_next)
  end

  def test_hours_in_day
  end

  def test_days_in_week
  end

  def test_unacknowledged
  end

end

class TcMauveNotification < Test::Unit::TestCase 

  def test_notify
    t = Time.now

    config=<<EOF

server {
  database "sqlite::memory:"
}

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
    during { @test_time.to_i >= #{(t + 1.hour).to_i}   }
    every 10.minutes
  }
  
  notify("test3") {
    during { unacknowledged( 2.hours ) }
    every 10.minutes
  }

}
EOF

    
    assert_nothing_raised { 
      Mauve::Configuration.current = Mauve::ConfigurationBuilder.parse(config) 
      Mauve::Server.instance.setup
      alert = Mauve::Alert.new(
        :alert_id  => "test", 
        :source    => "test",
        :subject   => "test"
      )
      alert.raise!
    }

    assert_equal(1, Mauve::Alert.count)

    reminder_times = {
      "test1" => t + 10.minutes,
      "test2" => t + 1.hour,
      "test3" => t + 2.hours
    }

    Mauve::AlertChanged.all.each do |a|
      pp a
      assert_equal("urgent", a.level, "Level is wrong")
      assert_equal("raised", a.update_type, "Update type is wrong")
      assert_in_delta(reminder_times[a.person].to_f, a.remind_at.to_time.to_f, 10.0, "reminder time is wrong for #{a.person}")
    end
  end

end

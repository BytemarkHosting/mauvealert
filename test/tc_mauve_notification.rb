$:.unshift "../lib"

require 'test/unit'
require 'mauve/alert'
require 'mauve/notification'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/mauve_time'
require 'th_mauve_resolv'
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
    now = Mauve::MauveTime.now 
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
  end

  def remind_at_next
  end

end



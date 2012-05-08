$: << "../lib/"

require 'th_mauve'
require 'mauve/mauve_time'
require 'pp'

class TestMauveTime < Mauve::UnitTest

  def test_in_x_hours

    #
    # 5:44pm on a Friday
    #
    t = Time.local(2011,6,3,17,44,32)

    #
    # Working hours..
    #
    hour_0 = Time.local(2011,6,6,9,30,0)
    hour_1 = Time.local(2011,6,6,10,30,0)

    assert_equal(hour_1, t.in_x_hours(1,"working"))
    assert_equal(hour_0, t.in_x_hours(0,"working"))
    
    #
    # 4.45pm on a Friday
    #
    t = Time.local(2011,6,3,16,45,32)

    #
    # Working hours..
    #
    hour_0 = Time.local(2011,6,3,16,45,32)
    hour_1 = Time.local(2011,6,6,9,45,32)

    assert_equal(hour_1, t.in_x_hours(1,"working"))
    assert_equal(hour_0, t.in_x_hours(0,"working"))
  end

  def test_bank_holiday?
    x = Time.now
    assert(!x.bank_holiday?)

    x.bank_holidays << Date.new(x.year, x.month, x.day)
    assert(x.bank_holiday?)
  end

  def test_dead_zone?
    x = Time.local(2012,5,2,4,30,0)
    assert(x.dead_zone?)
    
    x = Time.local(2012,5,2,9,30,0)
    assert(!x.dead_zone?)
  end

  def test_daytime_hours
    x = Time.local(2012,5,2,4,30,0)
    assert(!x.daytime_hours?)

    x = Time.local(2012,5,2,9,30,0)
    assert(x.daytime_hours?)
  end


end

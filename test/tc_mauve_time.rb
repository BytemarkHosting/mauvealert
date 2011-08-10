$: << "../lib/"

require 'test/unit'
require 'mauve/mauve_time'
require 'pp'

class TestMauveTime < Test::Unit::TestCase

  def test_in_x_hours

    #
    # 5pm on a Friday
    #
    t = Time.local(2011,6,3,17,14,32)

    #
    # Working hours..
    #
    hour_0 = Time.local(2011,6,6,8,30,0)
    hour_1 = Time.local(2011,6,6,9,30,0)

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
    hour_1 = Time.local(2011,6,6,9,15,32)

    assert_equal(hour_1, t.in_x_hours(1,"working"))
    assert_equal(hour_0, t.in_x_hours(0,"working"))


  end


end

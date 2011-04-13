$: << "../lib/"

require 'test/unit'
require 'mauve/notification'

# Test changes to notification things.
class MauveNotificationTest < Test::Unit::TestCase

  def test_x_in_list_of_y
    mdr = Mauve::DuringRunner.new(Time.now)
    [
      [[0,1,3,4], 2, false],
      [[0,2,4,6], 2, true],
      [[0..1,3..6],2, false],
      [[0..2, 4,5],2, true],
      [[0,1..3], 2, true],
    ].each do |y,x,result|
      assert_equal(result, mdr.send(:x_in_list_of_y, x,y))
    end
  end

  def test_hours_in_day
    t = Time.gm(2010,1,2,3,4,5)
    # => Sat Jan 02 03:04:05 UTC 2010
    mdr = Mauve::DuringRunner.new(t)
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
      assert_equal(result, mdr.send(:hours_in_day, hours))
    end
  end

  def test_days_in_week
    t = Time.gm(2010,1,2,3,4,5)
    # => Sat Jan 02 03:04:05 UTC 2010
    mdr = Mauve::DuringRunner.new(t)
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
      assert_equal(result, mdr.send(:days_in_week, days), "#{t.wday} in #{days.join(", ")}")
    end
  end
end    

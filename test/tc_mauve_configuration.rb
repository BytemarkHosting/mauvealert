$:.unshift "../lib/"

require 'th_mauve'
require 'mauve/configuration'

class TcMauveConfiguration < Mauve::UnitTest
  include Mauve

  def setup
    setup_logger
  end

  def teardown
    teardown_logger
  end

  def test_do_parse_range
    [
      [[1.0...2.0], 1],
      [[1.0...3.0], 1..2],
      [[1.0...2.0], 1...2],
      [[1.0...2.0, 4.0...7.0],  [1, 4..6]],
      [[1.0..1.0], 1.0],
      [[1.0..2.0], 1.0..2.0],
      [[1.0...2.0], 1.0...2.0],
      [[1.0..1.0, 4.0..6.0],  [1.0, 4.0..6.0]],
      [[7.0...24.0, 0.0...7.0], 7..6],
      [[6.0...7.0, 0.0...1.0], 6..0, 0...7],
      [["x".."z", "a".."c"], "x".."c", "a".."z"]
    ].each do |output, *input|
      c = Configuration.new
      assert_equal(output, c.__send__("do_parse_range",*input))
    end
  end

end



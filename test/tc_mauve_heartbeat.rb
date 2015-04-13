# encoding: utf-8

$:.unshift "../lib"

require 'th_mauve'
require 'th_mauve_resolv'
require 'mauve/server'
require 'mauve/heartbeat'

class TcMauveHeartbeat < Mauve::UnitTest
  include Mauve

  def test_errors_on_bad_destination
    heartbeat = Heartbeat.instance
    assert_raises(ArgumentError) do
      heartbeat.destination = 1
    end
  end
end


$:.unshift "../lib"

require 'th_mauve'
require 'mauve/person'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'
require 'pp' 

class TcMauvePerson < Mauve::UnitTest 

  def setup
    super
    setup_database
  end

  def teardown
    teardown_database
    super
  end

  def test_suppressed?

  end

  def test_send_alert

  end

  def test_do_send_alert

  end

  def test_current_alerts

  end

  def test_is_on_holiday? 

  end
end




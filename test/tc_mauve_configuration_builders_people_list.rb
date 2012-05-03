$:.unshift "../lib/"

require 'th_mauve'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders/people_list'

class TcMauveConfigurationBuildersPeopleList < Mauve::UnitTest

  def setup
    setup_logger
  end

  def teardown
    teardown_logger
  end

  def test_people_list
    config =<<EOF
people_list("team sky", %w(
  geraint
  edvald
  bradley
  rigoberto
  ben
))

people_list("garmin-cervelo", %w(
  thor
  ryder
  tyler
  julian
)) {
  notify {
    every 20.minutes
    during { working_hours?  }
  }
}

EOF
    x = nil
    assert_nothing_raised { x = Mauve::ConfigurationBuilder.parse(config) }
    assert_equal(2, x.people.keys.length)
    assert_equal(["team sky","garmin-cervelo"].sort,x.people.keys.sort)
    assert_equal(%w(geraint edvald bradley rigoberto ben), x.people["team sky"].list)
  end

  def test_duplicate_people_list

    config=<<EOF

people_list "htc-highroad", 
  ["mark c", "mark r", "Lars"]

people_list "htc-highroad",
  %w(Bernie Danny Lars)

EOF
    x = nil
    #
    # This should generate two warnings:
    #   * duplicate list
    #   * Lars already being on a list
    #
    assert_raise(ArgumentError) { x = Mauve::ConfigurationBuilder.parse(config) }
  end

end

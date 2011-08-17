$:.unshift "../lib/"

require 'th_mauve'
require 'mauve/configuration_builder'

class TcMauveConfigurationBuildersPeopleAndSourceLists < Mauve::UnitTest

  def setup
    setup_logger
  end

  def teardown
    teardown_logger
  end

  def test_people_list
    config =<<EOF
people_list "team sky", %w(
  geraint
  edvald
  bradley
  rigoberto
  ben
)

people_list "garmin-cervelo", %w(
  thor
  ryder
  tyler
  julian
)

EOF
    x = nil
    assert_nothing_raised { x = Mauve::ConfigurationBuilder.parse(config) }
    assert_equal(2, x.people_lists.keys.length)
    assert_equal(["team sky","garmin-cervelo"].sort,x.people_lists.keys.sort)
    assert_equal(%w(geraint edvald bradley rigoberto ben), x.people_lists["team sky"].list)

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
    assert_nothing_raised { x = Mauve::ConfigurationBuilder.parse(config) }

    assert_match(/Lars/,      logger_pop())
    assert_match(/Duplicate/, logger_pop())

    assert_equal(1, x.people_lists.keys.length)
    assert_equal(["mark c","mark r","Lars","Bernie","Danny"].sort, x.people_lists["htc-highroad"].list.sort)
  end

  def test_source_list
    config =<<EOF
source_list "sources", %w(
  test-1.example.com
  imaginary.host.example.com
  192.168.100.1/24
  *.imaginary.example.com
)
EOF

    x = nil
    assert_nothing_raised { x = Mauve::ConfigurationBuilder.parse(config) }

    x.source_lists["sources"].resolve
  end

end

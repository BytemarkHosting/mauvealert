$:.unshift "../lib/"

require 'th_mauve'
require 'mauve/configuration_builder'

class TcMauveConfigurationBuilder < Mauve::UnitTest

  def setup
    super
    setup_logger
  end

  def teardown
    super
    teardown_logger
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

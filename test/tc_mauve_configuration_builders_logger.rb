$:.unshift "../lib/"

require 'th_mauve'
require 'mauve/configuration_builders/logger'

class TcMauveConfigurationBuildersLogger < Mauve::UnitTest

  def setup
  end

  def test_load

    config=<<EOF
logger {
  default_format "%d [ %l ] [ %12.12c ] %m"
  default_level WARN

  outputter "stdout"

  outputter ("file") {
    trunc false
    filename "test.conf"
    level DEBUG
  }

}
EOF

    assert_nothing_raised { Mauve::ConfigurationBuilder.parse(config) }
    
    #
    # Check that we've got the correct things set
    #
    logger = nil
    assert_nothing_raised { logger = Log4r::Logger.get("Mauve") }
    assert_equal(2, logger.outputters.length)

    outputter = logger.outputters[0]

    assert_kind_of(Log4r::StdoutOutputter, outputter)
    assert_equal("%d [ %l ] [ %12.12c ] %m", outputter.formatter.pattern )
    assert_equal(Log4r::WARN, outputter.level )

    outputter = logger.outputters[1]
    assert_kind_of(Log4r::FileOutputter, outputter)
    assert_equal("%d [ %l ] [ %12.12c ] %m", outputter.formatter.pattern )
    assert_equal(Log4r::DEBUG, outputter.level )
    assert_equal(false, outputter.trunc )
    assert_equal("test.conf", outputter.filename )
  end

  def test_levels
    #
    # Make sure our levels match those of log4r.
    #
    %w(DEBUG WARN FATAL ERROR INFO).each do |l|
      assert_equal(Log4r.const_get(l), Mauve::LoggerConstants.const_get(l))
    end
  end

end

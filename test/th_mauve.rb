require 'test/unit'
require 'timecop'
require 'log4r'
require 'pp'
require 'singleton'

# Taken from
#
# http://blog.ardes.com/2006/12/11/testing-singletons-with-ruby
#
class << Singleton

  def included_with_reset(klass)
    included_without_reset(klass)
    class << klass
      def reset_instance
        Singleton.send :__init__, self
        self
      end
    end
  end

  alias_method :included_without_reset, :included
  alias_method :included, :included_with_reset
end

module Mauve
  class TestOutputter < Log4r::Outputter
    def initialize( _name, hash={})
      @buffer = []
      super
    end

    def pop     ; @buffer.pop     ; end
    def shift ; @buffer.shift ; end

    def write(data)
      @buffer << data
    end

    def flush
      print "\n" if @buffer.length > 0
      while d = @buffer.shift
        print d
      end
    end

  end
end


module Mauve
  class UnitTest < Test::Unit::TestCase

    def setup
      reset_all_singletons
      reset_mauve_configuration
      setup_logger
      setup_time
    end

    def teardown
      teardown_logger
      teardown_time
      reset_all_singletons
    end

    def setup_logger
      @logger      = Log4r::Logger.new 'Mauve'
      @outputter   = Mauve::TestOutputter.new("test")
      @outputter.formatter = Log4r::PatternFormatter.new( :pattern => "%d %l %m" )
      @outputter.level = case ENV['LOGLEVEL']
        when "DEBUG"
          Log4r::DEBUG
        when "INFO"
          Log4r::INFO
        else
          Log4r::WARN
      end
      @logger.outputters   << @outputter
      return @logger
    end

    def logger_pop
      @outputter.pop
    end

    def logger_shift
      @outputter.shift
    end

    def teardown_logger
      logger = Log4r::Logger['Mauve']
      return if logger.nil?

      o = logger.outputters.find{|o| o.name == "test"}
      o.flush if o.respond_to?("flush")
      # Delete the logger.
      Log4r::Logger::Repository.instance.loggers.delete('Mauve')
    end

    def setup_database
      DataMapper::Model.raise_on_save_failure = true if defined?(DataMapper::Model)
    end

    def teardown_database
      DataObjects::Pooling.pools.each{|pool| pool.dispose} if defined?(DataObjects::Pooling)
    end

    def setup_time
      Timecop.freeze(Time.local(2011,8,1,0,0,0,0))
    end

    def teardown_time
      Timecop.return
    end

    def reset_mauve_configuration
      Mauve::Configuration.current = Mauve::Configuration.new if defined?(Mauve::Configuration)
    end

    def reset_all_singletons
      Mauve.constants.collect{|const| Mauve.const_get(const)}.each do |klass|
        next unless klass.respond_to?(:instance)
        klass.reset_instance
      end
    end

    def default_test
      #
      #
      flunk("No tests specified") unless self.class == Mauve::UnitTest
    end

  end
end

# encoding: UTF-8
require 'log4r'
require 'mauve/configuration_builder'

module Mauve
  module ConfigurationBuilders

    class LoggerOutputter < ObjectBuilder

      # Set up a Log4r::Outputter
      #
      # @param [String] outputter Outputter basic class name, like Stderr, Stdin, File.
      #
      def builder_setup(outputter)
        @outputter = outputter.capitalize+"Outputter"

        begin
          Log4r.const_get(@outputter)
        rescue NameError
          require "log4r/outputter/#{@outputter.downcase}"
        end

        @outputter_name = anonymous_name

        @args = {}
      end

      # The new outputter
      #
      # @return [Log4r::Outputter]
      def result
        @result ||= Log4r.const_get(@outputter).new("Mauve", @args)
      end

      # Set the formatter for this outputter (see Log4r::PatternFormatter for
      # allowed patterns).  SyntaxError is caught in the ObjectBuilder#parse
      # method.
      # 
      # @param [String] f The format
      #
      # @return [Log4r::PatternFormatter]
      def format(f)
        result.formatter = Log4r::PatternFormatter.new(:pattern => f)
      end

      # This is needed to be able to pass arbitrary arguments to Log4r
      # outputters.  Missing methods / bad arguments are caught in the
      # ObjectBuilder#parse method.
      #
      # @param [String] name
      # @param [Object] value
      #
      def method_missing(name, value=nil)
        if value.nil?
          result.send(name.to_sym)
        else
          @args[name.to_sym] = value
        end
      end

    end

    class Logger < ObjectBuilder

      is_builder "outputter", LoggerOutputter

      # Set up the new logger
      #
      def builder_setup
        @result         = Log4r::Logger['Mauve'] || Log4r::Logger.new('Mauve')
        @default_format = nil
        @default_level  = Log4r::RootLogger.instance.level
      end

      # Set the default format.  Syntax erros are caught in the
      # ObjectBuilder#parse method.
      #
      # @param [String] f Any format pattern allowed by Log4r::PatternFormatter.
      #
      # @return [Log4r::PatternFormatter]
      def default_format(f)
        @default_formatter = Log4r::PatternFormatter.new(:pattern => f)

        #
        # Set all current outputters
        #
        result.outputters.each do |o|
          o.formatter = @default_formatter if o.formatter.is_a?(Log4r::DefaultFormatter)
        end

        @default_formatter
      end

      # Set the default log level.
      #
      # @param [Integer] l The log level.
      # @raise [ArgumentError] If the log level is bad
      #
      # @return [Integer] The log level set.
      def default_level(l)
        if Log4r::Log4rTools.valid_level?(l)
          @default_level = l
        else
          raise ArgumentError.new "Bad default level set for the logger #{l.inspect}"
        end

        result.outputters.each do |o|
          o.level = @default_level if o.level == Log4r::RootLogger.instance.level
        end

        @default_level
      end

      # This is called once an outputter has been created.  It sets the default
      # formatter and level, if these have been already set.
      #
      # @param [Log4r::Outputter] outputter Newly created outputter.
      #
      # @return [Log4r::Outputter] The adjusted outputter.
      def created_outputter(outputter)
        #
        # Set the formatter and level for any newly created outputters
        #
        if @default_formatter
          outputter.formatter = @default_formatter if outputter.formatter.is_a?(Log4r::DefaultFormatter)
        end

        if @default_level
          outputter.level = @default_level if outputter.level == Log4r::RootLogger.instance.level
        end

        result.outputters << outputter
      end
    end
  end

  # 
  # this should live in Logger but can't due to
  # http://briancarper.net/blog/ruby-instance_eval_constant_scoping_broken
  #
  module LoggerConstants
    Log4r.define_levels(*Log4r::Log4rConfig::LogLevels) # ensure levels are loaded

    # Debug logging
    DEBUG = Log4r::DEBUG
    # Info logging
    INFO  = Log4r::INFO
    # Warn logging
    WARN  = Log4r::WARN
    # Error logging
    ERROR = Log4r::ERROR
    # Fatal logging
    FATAL = Log4r::FATAL
  end

  class ConfigurationBuilder < ObjectBuilder

    include LoggerConstants

    is_builder "logger", ConfigurationBuilders::Logger

  end
end

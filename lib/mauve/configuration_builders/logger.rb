# encoding: UTF-8
require 'log4r'
require 'mauve/configuration_builder'

module Mauve
  module ConfigurationBuilders

    class LoggerOutputter < ObjectBuilder

      def builder_setup(outputter)
        @outputter = outputter.capitalize+"Outputter"

        begin
          Log4r.const_get(@outputter)
        rescue
          require "log4r/outputter/#{@outputter.downcase}"
        end

        @outputter_name = "Mauve-"+5.times.collect{rand(36).to_s(36)}.join

        @args = {}
      end

      def result
        @result ||= Log4r.const_get(@outputter).new("Mauve", @args)
      end

      def format(f)
        result.formatter = Log4r::PatternFormatter.new(:pattern => f)
      end

      #
      # This is needed to be able to pass arbitrary arguments to Log4r
      # outputters.
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

      def builder_setup
        @result         = Log4r::Logger.new('Mauve')
        @default_format = nil
        @default_level  = Log4r::RootLogger.instance.level
      end

      def default_format(f)
        begin
          @default_formatter = Log4r::PatternFormatter.new(:pattern => f)
        rescue SyntaxError 
          raise BuildException.new "Bad log format #{f.inspect}"
        end
        #
        # Set all current outputters
        #
        result.outputters.each do |o|
          o.formatter = @default_formatter if o.formatter.is_a?(Log4r::DefaultFormatter)
        end
      end

      def default_level(l)
        if Log4r::Log4rTools.valid_level?(l)
          @default_level = l
        else
          raise "Bad default level set for the logger #{l}.inspect"
        end

        result.outputters.each do |o|
          o.level = @default_level if o.level == Log4r::RootLogger.instance.level
        end
      end

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

    DEBUG = Log4r::DEBUG
    INFO  = Log4r::INFO
    WARN  = Log4r::WARN
    ERROR = Log4r::ERROR
    FATAL = Log4r::FATAL
  end

  class ConfigurationBuilder < ObjectBuilder

    include LoggerConstants

    is_builder "logger", ConfigurationBuilders::Logger

  end
end

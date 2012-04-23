# encoding: UTF-8
require 'object_builder'
require 'mauve/configuration'
require 'mauve/people_list'
require 'mauve/source_list'

module Mauve
  #
  # This is the top-level configuration builder
  #
  class ConfigurationBuilder < ObjectBuilder

    # This overwrites the default ObjectBuilder initialize method, such that
    # the context is set as a new configuration
    #
    def initialize
      @context = @result = Configuration.new
      # FIXME: need to test blocks that are not immediately evaluated
    end

    # Adds a source list
    #
    # @param [String] label
    # @param [Array]  list
    #
    # @return [Array] the whole source list for label
    def source_list(label, *list)
      _logger.warn "Duplicate source_list '#{label}'" if @result.source_lists.has_key?(label)
      @result.source_lists[label] += list
    end

    # Adds a people list
    #
    # @param [String] label
    # @param [Array]  list
    #
    # @return [Array] the whole people list for label
    # ef people_list(label, *list)
    #  _logger.warn("Duplicate people_list '#{label}'") if @result.people_lists.has_key?(label)
    #  @result.people_lists[label] += list
    # end


    # Have to use the method _logger here, cos logger is defined as a builder elsewhere.
    #
    # @return [Log4r::Logger]
    def _logger
      @logger ||= Log4r::Logger.new(self.class.to_s)
    end

  end

end

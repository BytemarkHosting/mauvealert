# encoding: UTF-8
require 'object_builder'
require 'mauve/people_list'
require 'mauve/configuration_builder'

module Mauve
  module ConfigurationBuilders

    class PeopleList < ObjectBuilder

      def builder_setup(label, list)
        @result = Mauve::PeopleList.new(label)
        @result += list
      end

      is_block_attribute "during"
      is_attribute "every"

    end
  end

  class ConfigurationBuilder < ObjectBuilder

    is_builder "people_list", ConfigurationBuilders::PeopleList

    # Method called once a people_list has been created to check for duplicate labels
    #
    # @param [Mauve::PeopleList] people_list
    #
    def created_people_list(people_list)
      label = people_list.label
      if @result.people_lists.has_key?(label)
        _logger.warn("Duplicate people_list '#{label}'") 
        @result.people_lists[label] += people_list.list
      else
        @result.people_lists[label] = people_list
      end
    end

  end
end

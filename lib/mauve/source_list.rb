# encoding: UTF-8
require 'log4r'
require 'resolv-replace'

module Mauve

  # A simple construct to match sources.
  #
  # This class stores mamed lists of IP addresses.  It stores them in a hash
  # indexed by the name of the list.  One can pass IPv4, IPv6 and hostnames
  # as list elements but they will all be converted into IP addresses at 
  # the time of the list creation.
  #
  # One can ask if an IPv4, IPv6, hostname or url (match on hostname only) is
  # contained within a list.  If the query is not an IP address, it will be
  # converted into one before the checks are made.
  #
  # Note that the matching is greedy.  When a hostname maps to several IP
  # addresses and only one of tbhose is included in the list, a match 
  # will occure.  
  #
  # @author Yann Golanski
  class SourceList

    # Accessor, read only.  Use create_new_list() to create lists.
    attr_reader :hash

    ## Default contructor.
    def initialize ()
      @logger = Log4r::Logger.new "Mauve::SourceList"
      @hash = Hash.new
      @http_head = Regexp.compile(/^http[s]?:\/\//)
      @http_tail = Regexp.compile(/\/.*$/)
    end

    ## Return whether or not a list contains a source.
    #
    # @param [String] lst The list name.
    # @param [String] src The hostname or IP of the source.
    # @return [Boolean] true if there is such a source, false otherwise.
    def does_list_contain_source?(lst, src)
      raise ArgumentError.new("List name must be a String, not a #{lst.class}") if String != lst.class
      raise ArgumentError.new("Source name must be a String, not a #{src.class}") if String != src.class
      raise ArgumentError.new("List #{lst} does not exist.") if false == @hash.has_key?(lst)
      if src.match(@http_head)
        src = src.gsub(@http_head, '').gsub(@http_tail, '')
      end
      begin
        Resolv.getaddresses(src).each do |ip|
          return true if @hash[lst].include?(ip)
        end
      rescue Resolv::ResolvError, Resolv::ResolvMauveTimeout => e
        @logger.warn("#{lst} could not be resolved because #{e.message}.")
        return false
      rescue => e
        @logger.error("Unknown exception raised: #{e.class} #{e.message}")
        return false
      end
      return false
    end

    ## Create a list.
    # 
    # Note that is no elements give IP addresses, we have an empty list. 
    # This gets logged but otherwise does not stop mauve from working.
    #
    # @param [String] name The name of the list.
    # @param [Array] elem A list of source either hostname or IP.
    def create_new_list(name, elem)
      raise ArgumentError.new("Name of list is not a String but a #{name.class}") if String != name.class
      raise ArgumentError.new("Element list is not an Array but a #{elem.class}") if Array != elem.class
      raise ArgumentError.new("A list called #{name} already exists.") if @hash.has_key?(name)
      arr = Array.new
      elem.each do |host| 
        begin
          Resolv.getaddresses(host).each do |ip|
            arr << ip
          end
        rescue Resolv::ResolvError, Resolv::ResolvMauveTimeout => e
          @logger.warn("#{host} could not be resolved because #{e.message}.")
        rescue => e 
          @logger.error("Unknown exception raised: #{e.class} #{e.message}")
        end
      end
      @hash[name] = arr.flatten.uniq.compact
      if true == @hash[name].empty?
        @logger.error("List #{name} is empty! "+
                      "Nothing from element list '#{elem}' "+
                      "has resolved to anything useable.")
      end
    end

  end

  ## temporary object to convert from configuration file to the SourceList class
  class AddSoruceList < Struct.new(:label, :list)

    # Default constructor.
    def initialize (*args)
      super(*args)
    end

  end

end

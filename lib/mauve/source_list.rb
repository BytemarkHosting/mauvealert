# encoding: UTF-8
require 'log4r'
require 'ipaddr'
require 'uri'
require 'mauve/mauve_time'
require 'mauve/mauve_resolv'

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

    attr_reader :label, :list

    ## Default contructor.
    def initialize (label)
      @label            = label
      @last_resolved_at = nil
      @list = []
      @resolved_list = []
    end

    alias username label

    def +(l)
      arr = [l].flatten.collect do |h|
        # "*"              means [^\.]+
        # "(\d+)\.\.(\d+)" is expanded to every integer between $1 and $2
        #                  joined by a pipe, e.g. 1..5 means 1|2|3|4|5
        #  "."              is literal, not a single-character match
        if h.is_a?(String) and (h =~ /[\[\]\*]/ or h =~ /(\d+)\.\.(\d+)/)
          Regexp.new(
              h.
              gsub(/(\d+)\.\.(\d+)/) { |a,b|
                ($1.to_i..$2.to_i).collect.join("|")
              }.
              gsub(/\./, "\\.").
              gsub(/\*/, "[0-9a-z\\-]+") +
              "\\.?$")
        elsif h.is_a?(String) and h =~ /^[0-9a-f\.:\/]+$/i
          IPAddr.new(h)
        else
          h
        end
      end.flatten

      arr.each do |source|
        ##
        # I would use include? here, but IPAddr tries to convert "foreign"
        # classes to intgers, and RegExp doesn't have a to_i method..
        #
        if @list.any?{|e| source.is_a?(e.class) and source == e}
          logger.warn "#{source} is already on the #{self.label} list"
        else
          @list << source
        end
      end

      @resolved_list    = [] 
      @last_resolved_at = nil

      self
    end

    alias add_to_list +

    def logger
      @logger ||= Log4r::Logger.new self.class.to_s
    end

    ## 
    # Return whether or not a list contains a source.
    ##
    def includes?(host)
      #
      # Redo resolution every thirty minutes
      #
      resolve if @resolved_list.empty? or @last_resolved_at.nil? or (Time.now - 1800) > @last_resolved_at

      #
      # Pick out hostnames from URIs.
      #
      if host =~ /^[a-z][a-z0-9+-]+:\/\//
        begin      
          uri = URI.parse(host)
          host = uri.host unless uri.host.nil?
        rescue URI::InvalidURIError => ex
          # ugh
          logger.warn "Did not recognise URI #{host}"
        end
      end

      return true if @resolved_list.any? do |l|
        case l
          when String
            host == l
          when Regexp
            host =~ l
          when IPAddr 
            begin
              l.include?(IPAddr.new(host))
            rescue ArgumentError
              # rescue random IPAddr argument errors
              false
            end
          else
            false
        end
      end

      return false unless @resolved_list.any?{|l| l.is_a?(IPAddr)}

      ips = MauveResolv.get_ips_for(host).collect{|i| IPAddr.new(i)}

      return false if ips.empty?

      return @resolved_list.select{|i| i.is_a?(IPAddr)}.any? do |list_ip| 
        ips.any?{|ip| list_ip.include?(ip)}
      end
      
    end

    def resolve
      @last_resolved_at = Time.now

      new_list = @list.collect do |host| 
        if host.is_a?(String)
          ips = [host] + MauveResolv.get_ips_for(host).collect{|i| IPAddr.new(i)}
        else
          host
        end
      end
      @resolved_list = new_list.flatten
    end
  end

end

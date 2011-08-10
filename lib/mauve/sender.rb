# encoding: UTF-8
require 'ipaddr'
require 'socket'
require 'mauve/mauve_resolv'
require 'mauve/mauve_time'

module Mauve 
  class Sender
    DEFAULT_PORT = 32741

    include Resolv::DNS::Resource::IN
    
    def initialize(*destinations)
      destinations = destinations.flatten
      
      destinations = begin
        File.read("/etc/mauvealert/mauvesend.destination").split(/\s+/)
      rescue Errno::ENOENT => notfound
        []
      end if destinations.empty?
      
      if !destinations || destinations.empty?
        raise ArgumentError.new("No destinations specified, and could not read any destinations from /etc/mauvealert/mauvesend.destination")
      end
    
      #
      # Resolv results
      #
      results = []
      destinations.each do |spec|
        case spec
          when /^((?:\d{1,3}\.){3}\d{1,3})(?::(\d+))?$/
            #
            # IPv4 with a port
            #
            results << [$1, $2 || DEFAULT_PORT]

          when /^\[([0-9a-f:\.]{2,39})\](?::(\d+))?$/i
            #
            # IPv6 with a port
            #
            results << [$1, $2 || DEFAULT_PORT]

          when /^([^: ]+)(?::(\d+))?/
            domain = $1

            #
            # If no port is specified, set it to the default, and also try to
            # use SRV records.
            #
            if $2.nil?
              port = DEFAULT_PORT
              use_srv = true
            else
              port = $2
              use_srv = false
            end

            list = []
            Resolv::DNS.open do |dns|
              if use_srv
                #
                # Search for SRV records first.  If the first character of the
                # domain is an underscore, assume that it is a SRV record
                #
                srv_domain = (domain[0] == ?_ ? domain : "_mauvealert._udp.#{domain}")
  
                list += dns.getresources(srv_domain, SRV).map do |srv|
                  [srv.target.to_s, srv.port]
                end
              end
            end
            #
            # If nothing found, just use the domain and port
            #
            list = [[domain, port]] if list.empty?

            list.each do |d,p|
              r = []
              #
              # This gets both AAAA and A records
              #
              Mauve::MauveResolv.get_ips_for(d).each do |a|
                 r << [a, p]
              end

              results += r unless r.empty?
            end
        end ## case
      end ## each

      #
      # Validate results.
      #
      @destinations = []

      results.each do |ip, port|
        ip = IPAddr.new(ip)
        @destinations << [ip, port.to_i]
      end

    end

    #
    # Returns the number of packets sent.
    #
    def send(update, verbose=0)

      #
      # Must have a source, so default to hostname if user doesn't care 
      update.source ||= Socket.gethostname
      
      #
      # Make sure all alerts default to "-r now"
      #
      update.alert.each do |alert|
        next if alert.raise_time || alert.clear_time
        alert.raise_time = Time.now.to_i
      end
     
      #
      # Make sure we set the transmission time
      #
      update.transmission_time = Time.now.to_i 

      data = update.serialize_to_string

      if verbose == 1
        summary = "#{update.transmission_id} from #{update.source}"
      elsif verbose >= 2
        summary = update.inspect.split("\n").join(" ")
      end

      if verbose > 0
        puts "Sending #{summary} to #{@destinations.collect{|i,p| (i.ipv6? ? "[#{i}]" : i.to_s )+":#{p}"}.join(", ")}"
      end

      #
      # Keep a count of the number of alerts sent.
      #
      sent = 0

      @destinations.each do |ip, port|
        begin
          UDPSocket.open(ip.family).send(data, 0, ip.to_s, port)
          sent += 1
        rescue Errno::ENETUNREACH => ex
          # Catch and ignore unreachable network errors.
          warn "Got #{ex.to_s} whilst trying to send to "+(ip.ipv6? ? "[#{ip}]" : ip.to_s )+":#{port}" if verbose > 0
        end
      end

      raise "Failed to send any packets to any destinations!" unless sent > 0

      sent
    end
  end
end


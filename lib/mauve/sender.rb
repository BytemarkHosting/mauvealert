# encoding: UTF-8
require 'ipaddr'
require 'resolv'
require 'socket'
require 'mauve/mauve_time'
require 'pp'

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

          when /^\[?([0-9a-f:]{2,39})\]??$/i
            #
            # IPv6 without a port
            #
            results << [$1, $2 || DEFAULT_PORT]

          when /^\[([0-9a-f:]{2,39})\](?::(\d+))?$/i
            #
            # IPv6 with a port
            #
            results << [$1, $2 || DEFAULT_PORT]

          when /^([^: ]+)(?::(\d+))?/
            domain = $1
            port   = $2 || DEFAULT_PORT

            Resolv::DNS.open do |dns|
              #
              # Search for SRV records first.  If the first character of the
              # domain is an underscore, assume that it is a SRV record
              #
              srv_domain = (domain[0] == ?_ ? domain : "_mauvealert._udp.#{domain}")

              list = dns.getresources(srv_domain, SRV).map do |srv|
                [srv.target.to_s, srv.port]
              end

              #
              # If nothing found, just use the domain and port
              #
              list = [[domain, port]] if list.empty?

              list.each do |d,p|
                r = []

                #
                # Try IPv4 first.
                #
                dns.getresources(d, A).each do |a|
                  r << [a.address.to_s, p]
                end

                #
                # Try IPv6 too.
                #  
                dns.getresources(d, AAAA).map do |a|
                   r << [a.address.to_s, p]
                end 

                results += r unless r.empty?
              end
           end
        end
      end

      #
      # Validate results.
      #
      @destinations = []

      results.each do |ip, port|
        ip = IPAddr.new(ip)
        @destinations << [ip, port.to_i]
      end

    end
    
    def send(update, verbose=0)

      #
      # Must have a source, so default to hostname if user doesn't care 
      update.source ||= `hostname -f`.chomp
      
      #
      # Make sure all alerts default to "-r now"
      #
      update.alert.each do |alert|
        next if alert.raise_time || alert.clear_time
        alert.raise_time = MauveTime.now.to_i
      end
     
      #
      # Make sure we set the transmission time
      #
      update.transmission_time = MauveTime.now.to_i 

      data = update.serialize_to_string


      if verbose == 1
        print "#{update.transmission_id}\n"
      elsif verbose >= 2
        print "Sending #{update.inspect.chomp} to #{@destinations.join(", ")}\n"
      end

      @destinations.each do |ip, port|
        begin
          UDPSocket.open(ip.family) do |sock|
            sock.send(data, 0, ip.to_s, port)
          end
        rescue StandardError => ex
          warn "Got #{ex.to_s} whilst trying to send to #{ip} #{port}"
        end
      end
    end
  end
end


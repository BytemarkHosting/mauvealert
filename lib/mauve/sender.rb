# encoding: UTF-8
require 'ipaddr'
require 'resolv'
require 'socket'
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
    
      @destinations = destinations.map do |spec|
        next_spec = begin
          # FIXME: for IPv6
          port = spec.split(":")[1] || DEFAULT_PORT
          IPAddr.new(spec.split(":")[0])
          ["#{spec}:#{port}"]
        rescue ArgumentError => not_an_ip_address
          Resolv::DNS.open do |dns|
            srv_spec = spec[0] == ?_ ? spec : "_mauvealert._udp.#{spec}"
            list = dns.getresources(srv_spec, SRV).map do |srv|
              srv.target.to_s + ":#{srv.port}"
            end
            list = [spec] if list.empty?
            list.map do |spec2|
              spec2_addr, spec2_port = spec2.split(":")
              spec2_port ||= DEFAULT_PORT
              dns.getresources(spec2_addr, A).map do |a|
                "#{a.address}:#{spec2_port}"
              end
            end
          end
        end.flatten

        error "Can't resolve destination #{spec}" if next_spec.empty?

        next_spec
      end.
      flatten.
      uniq
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

      @destinations.each do |spec|
        UDPSocket.open do |sock|
          ip = spec.split(":")[0]
          port = spec.split(":")[1].to_i
          sock.send(data, 0, ip, port)
        end
      end
    end
  end
end


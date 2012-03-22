require 'resolv-replace'

module Mauve
  #
  # This is just a quick class to resolve a hostname to all its IPs, IPv6 and IPv4.
  #
  class MauveResolv

    class << self

      # Get all IPs for a host, both IPv6 and IPv4.  ResolvError and
      # ResolvTimeout are both rescued.
      #
      # @param [String] host The hostname 
      # @return [Array] Array of IP addresses, as Strings.
      #
      def get_ips_for(host)
        ips = []
        Resolv::DNS.open do |dns|
          %w(A AAAA).each do |type|
            self.count += 1 if $debug
            begin
              ips += dns.getresources(host, Resolv::DNS::Resource::IN.const_get(type)).collect{|a| a.address.to_s}
            rescue Resolv::ResolvError, Resolv::ResolvTimeout => e
              logger.warn("#{host} could not be resolved because #{e.message}.")
            end
          end
        end
        ips
      end

      def count
        @count ||= 0
      end

      def count=(c)
        @count = c
      end

      # @return [Log4r::Logger]
      def logger
        @logger ||= Log4r::Logger.new(self.to_s)
      end
    end
  end
end



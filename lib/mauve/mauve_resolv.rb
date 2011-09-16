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
        record_types = %w(A AAAA)
        ips = []

        %w(A AAAA).each do |type|
          begin
            Resolv::DNS.open do |dns|
              dns.getresources(host, Resolv::DNS::Resource::IN.const_get(type)).each do |a|
                 ips << a.address.to_s
              end
            end
          rescue Resolv::ResolvError, Resolv::ResolvTimeout => e
            logger.warn("#{host} could not be resolved because #{e.message}.")
          end
        end
        ips
      end

      # @return [Log4r::Logger]
      def logger
        @logger ||= Log4r::Logger.new(self.to_s)
      end
    end
  end
end



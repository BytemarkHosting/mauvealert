require 'resolv-replace'

#
#
#

module Mauve
  class MauveResolv
    class << self
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

      def logger
        @logger ||= Log4r::Logger.new(self.to_s)
      end
    end
  end
end



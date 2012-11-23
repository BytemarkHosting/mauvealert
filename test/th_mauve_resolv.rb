
$:.unshift "../lib"

require 'mauve/mauve_resolv'

#
# This allows us to specify IPs for test hostnames, and also to fall back on
# regular DNS if that fails.
#

module Mauve
  class MauveResolv
    class << self
      alias_method :get_ips_for_without_testing, :get_ips_for

      def get_ips_for_with_testing(host)

        lookup = {
         "test-1.example.com" => %w(1.2.3.4 2001:1:2:3::4),
         "test-2.example.com" => %w(1.2.3.5 2001:1:2:3::5),
         "www.example.com"    => %w(1.2.3.4),
         "www2.example.com"   => %w(1.2.3.5 2001:2::2)
        }
        if lookup.has_key?(host)
          self.count += lookup[host].length 
          lookup[host]
        else
          self.count += 1
          []
        end
      end

      alias_method :get_ips_for, :get_ips_for_with_testing
    end
  end
end


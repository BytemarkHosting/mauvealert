# encoding: UTF-8
require 'ipaddr'
require 'socket'
begin
  require 'locale'
rescue LoadError
  # Do nothing -- these are bonus libraries :)
end

require 'mauve/mauve_resolv'
require 'mauve/mauve_time'
require 'mauve/proto'

module Mauve
  #
  # This is the class that send the Mauve packets.
  #
  class Sender
    #
    # This is the default mauve receiving port.
    #
    DEFAULT_PORT = 32741

    include Resolv::DNS::Resource::IN

    # Set up a new sender.  It takes a list of destinations and uses DNS to
    # resolve names to addresses.
    #
    # A destination can look like
    #
    #   1.2.3.4:5678
    #   1.2.3.4
    #   [2001:1af:ba8::dead]:5678
    #   [2001:1af:ba8::dead]
    #   mauve.host:5678
    #   mauve.host
    #
    # If no port is specified, DEFAULT_PORT is used.
    #
    # If a hostname is used, SRV records are used, with the prefix
    # +_mauvealert._udp+ to determine the real hostname and port to which
    # alerts should be sent.
    #
    # Otherwise AAAA and A records are looked up.
    #
    # @param [Array] destinations List of destinations to which the update is to be sent.
    #
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

    # Sanitise all fields in an update, such that when we send, they are
    # normal.
    #
    #
    def sanitize(update)
      #
      # Must have a source, so default to hostname if user doesn't care
      update.source ||= Socket.gethostname

      #
      # Must have a `replace`.  We supply a default, but it doesn't
      # get used so if we want to use Sender outside of bin/mauvesend,
      # we have to manually add it here with an explicit `false`.
      # `nil` doesn't work.
      update.replace ||= false

      #
      # Check the locale charset.  This is to maximise the amout of information
      # mauve receives, rather than provide proper sanitized data for the server.
      #
      from_charset = (Locale.current.charset || Locale.charset) if defined?(Locale)
      from_charset ||= "UTF-8"

      #
      #
      #
      update.each_field do |field, value|
        #
        # Make sure all string fields are UTF8 -- to ensure the maximal amount of information is sent.
        #
        if value.respond_to?(:encode)
          value = value.encode("UTF-8", :undef => :replace, :invalid => :replace)
        end
        update.__send__("#{field.name}=", value)
      end

      update.alert.each do |alert|
        #
        # Make sure all alerts default to "-r now"
        #
        alert.raise_time = Time.now.to_i unless (alert.raise_time > 0 or alert.clear_time > 0)

        alert.each_field do |field, value|
          #
          # Make sure all string fields are UTF8 -- to ensure the maximal amount of information is sent.
          #
          if value.respond_to?(:encode)
            value = value.encode("UTF-8", :undef => :replace, :invalid => :replace)
          end
          alert.__send__("#{field.name}=", value)
        end
      end

      #
      # Make sure we set the transmission time and ID.
      #
      update.transmission_time = Time.now.to_i if update.transmission_time.nil? or update.transmission_time == 0
      update.transmission_id   = rand(2**63)   if update.transmission_id.nil? or update.transmission_id == 0

      update
    end

    # Send an update.
    #
    # @param [Mauve::Proto] update The update to send
    # @param [Integer] vebose The verbosity -- higher is more.
    #
    # @return [Integer] the number of packets sent.
    def send(update, verbose=0)
      #
      # Clean up the update, and set any missing fields.
      #
      update = sanitize(update)

      data = sanitize(update).serialize_to_string

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


# encoding: UTF-8
require 'yaml'
require 'socket'
require 'mauve/datamapper'
require 'mauve/proto'
require 'mauve/alert'
require 'ipaddr'

module Mauve

  #
  # This is the thread that accepts the packets.
  #
  class UDPServer < MauveThread

    include Singleton

    attr_reader   :ip, :port

    # Yup.  Creates a new UDPServer.
    #
    # Defaults:
    #   * listening IP: 127.0.0.1
    #   * listening port: 32741
    #   * polls every: 0 seconds
    #
    def initialize
      #
      # Set up some defaults.
      #
      self.ip     = "127.0.0.1"
      self.port   = 32741
      self.poll_every = 0
      @socket = nil

      super
    end
 
    #
    # This sets the IP which the server will listen on.
    # 
    # @param [String] i The new IP 
    # @return [IPAddr]
    #
    def ip=(i)
      raise ArgumentError, "ip must be a string" unless i.is_a?(String)
      @ip = IPAddr.new(i)
    end
 
    # Sets the listening port
    #
    # @param [Integer] pr The new port
    # @return [Integer]
    #
    def port=(pr)
      raise ArgumentError, "port must be an integer between 0 and #{2**16-1}" unless pr.is_a?(Integer) and pr < 2**16 and pr > 0
      @port = pr
    end
   
    # This stops the UDP server, by signalling to the thread to stop, and
    # sending a zero-length packet to the socket.
    #
    def stop
      @stop = true
      #
      # Triggers loop to close socket.
      #
      UDPSocket.open(Socket.const_get(@socket.addr[0])).send("", 0, @socket.addr[2], @socket.addr[1]) unless @socket.nil? or @socket.closed?

      super
    end

    private

    #
    # This opens the socket for listening.
    #
    # It tries to increase the default receiving buffer to 10M, and will warn
    # if this fails to increase the buffer at all.
    #
    # @return [Nilclass]
    #
    def open_socket
      #
      # Specify the family when opening the socket.
      #
      @socket = UDPSocket.new(@ip.family)
      
      logger.debug("Trying to increase Socket::SO_RCVBUF to 10M.")
      old = @socket.getsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF).unpack("i").first

      @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 10*1024*1024)
      new = @socket.getsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF).unpack("i").first

      logger.warn "Could not increase Socket::SO_RCVBUF.  Had #{old} ended up with #{new}!" if old > new 

      logger.debug("Successfully increased Socket::SO_RCVBUF from #{old} to #{new}.")

      @socket.bind(@ip.to_s, @port)

      logger.info("Opened socket on #{@ip.to_s}:#{@port}")
    end

    # This closes the socket.  IOErrors are caught and logged.
    #
    def close_socket
      return if @socket.nil?  or @socket.closed?

      begin
        @socket.close 
      rescue IOError => ex
        # Just in case there is some sort of explosion! 
        logger.error "Caught IOError #{ex.to_s}"
        logger.debug ex.backtrace.join("\n")
      end

      logger.info("Closed socket")
    end

    # This is the main loop.  It receives from the UDP port, and records the
    # time the packet arrives.  It then pushes the packet onto the Server's
    # packet buffer for the processor to pick up later.
    #
    # If a zero-length packet is received, and the thread has been signalled to
    # stop, then the socket is closed, and the thread exits.
    #
    def main_loop
      return if self.should_stop?

      open_socket if @socket.nil? or @socket.closed?

      return if self.should_stop? 

      #
      # TODO: why is/isn't this non-block?
      #
      i = 0
      begin
#        packet      = @socket.recvfrom_nonblock(65535)
        packet      = @socket.recvfrom(65535)
        received_at = Time.now
      rescue Errno::EAGAIN, Errno::EWOULDBLOCK => ex
        IO.select([@socket])
        retry unless self.should_stop?
      end

      return if packet.nil?

      logger.debug("Got new packet: #{packet.inspect}")

      #
      # If we get a zero length packet, and we've been flagged to stop, we stop!
      #
      if packet.first.length == 0 and self.should_stop?
        close_socket 
        return
      end

      #
      # Push packet onto central queue
      #
      Server.packet_push([packet[0], packet[1], received_at])
    end

  end

end

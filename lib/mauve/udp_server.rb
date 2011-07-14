# encoding: UTF-8
require 'yaml'
require 'socket'
require 'mauve/datamapper'
require 'mauve/proto'
require 'mauve/alert'
require 'ipaddr'

module Mauve

  class UDPServer < MauveThread

    include Singleton

    attr_accessor :ip, :port, :sleep_interval

    def initialize
      super
      # 
      # Set the logger up
      #
      @ip     = "127.0.0.1"
      @port   = 32741
      @socket = nil
      @closing_now = false
      @sleep_interval = 0
    end
  
    def open_socket
      # 
      # check the IP address
      #
      _ip = IPAddr.new(@ip)

      #
      # Specify the family when opening the socket.
      #
      @socket = UDPSocket.new(_ip.family)
      @closing_now = false
      
      logger.debug("Trying to increase Socket::SO_RCVBUF to 10M.")
      old = @socket.getsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF).unpack("i").first

      @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 10*1024*1024)
      new = @socket.getsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF).unpack("i").first

      raise "Could not increase Socket::SO_RCVBUF.  Had #{old} ended up with #{new}!" if old > new 

      logger.debug("Successfully increased Socket::SO_RCVBUF from #{old} to #{new}.")

      @socket.bind(@ip, @port)

      logger.info("Opened socket on #{@ip}:#{@port}")
    end

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
        received_at = MauveTime.now
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
        self.close_socket 
        return
      end

      #
      # Push packet onto central queue
      #
      Server.packet_push([packet[0], packet[1], received_at])
    end

    def stop
      @stop = true
      #
      # Triggers loop to close socket.
      #
      UDPSocket.open(Socket.const_get(@socket.addr[0])).send("", 0, @socket.addr[2], @socket.addr[1]) unless @socket.nil? or @socket.closed?

      super
    end

  end

end

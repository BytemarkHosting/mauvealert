# encoding: utf-8

$:.unshift "../lib"

require 'th_mauve'
require 'th_mauve_resolv'
require 'mauve/udp_server'
require 'mauve/server'

class TcMauveUdpServer < Mauve::UnitTest
  # Note: this test fires up the UDP socket.  It *will* fail if more
  # than one instance runs at the same time on the same machine.
  include Mauve

  def setup
    super
    Server.instance.packet_buffer.clear # blarg!
    @server = UDPServer.instance # blarg!
  end

  def test_listens
    update = generic_update()
    before = Time.now
    t = Thread.new do @server.__send__(:main_loop) end
    sleep(0.2)
    sender.send(update)
    Timeout.timeout(2) do t.join end
    after = Time.now
    data, addrinfo, received_at = Server.packet_pop
    assert_equal update, Proto::AlertUpdate.new.parse_from_string(data)
    assert addrinfo[3], "No client source address!"
    assert received_at >= before && received_at <= after, "Received at time was wrong"
  end

  def test_closes
    update = generic_update()
    t = @server.run
    sleep(0.2)
    @server.stop
    sleep(0.2)
    sender.send(update)
    Timeout.timeout(2) do t.join end
    assert_nil Server.packet_pop
  end


  def sender
    Sender.new(["#{@server.ip}:#{@server.port}"])
  end

  def generic_update
    update = Proto::AlertUpdate.new
    alert = Proto::Alert.new
    alert.id = "alertid"
    update.alert << alert
    update
  end

end

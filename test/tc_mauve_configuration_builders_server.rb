$:.unshift "../lib/"

require 'th_mauve'
require 'mauve/configuration_builders/server'

class TcMauveConfigurationBuildersServer < Mauve::UnitTest

  def test_server_params
    hostname = "test.example.com"
    database =  "sqlite://./test.db"
    initial_sleep = 314

    config=<<EOF
server {
  hostname "#{hostname}"
  database "#{database}"
  initial_sleep #{initial_sleep}
}
EOF

    assert_nothing_raised { Mauve::ConfigurationBuilder.parse(config) }
    
    #
    # Check that we've got the correct things set
    #
    s = Mauve::Server.instance
    assert_equal(hostname, s.hostname)
    assert_equal(database, s.database)
    assert_equal(initial_sleep, s.initial_sleep)
  end

  def test_heartbeat_params
    destination = "test-backup.example.com"
    summary     = "Mauve blurgh!"
    detail      = "<p>A very interesting test.</p>"
    raise_after = 1000
    send_every  = 60

    config=<<EOF
server {
  heartbeat {
    destination "#{destination}"
    summary     "#{summary}"
    detail      "#{detail}"
    raise_after #{raise_after}
    send_every  #{send_every}
  }
}
EOF
    assert_nothing_raised { Mauve::ConfigurationBuilder.parse(config) }

    h = Mauve::Heartbeat.instance
    assert_equal(detail, h.detail)
    assert_equal(summary, h.summary)
    assert_equal(destination, h.destination)
    assert_equal(raise_after, h.raise_after)
    assert_equal(send_every, h.send_every) 
  end

  def test_web_interface_params
    ip = "::"
    port = 12341
    document_root = "./"
    base_url = "http://www.example.com"
    session_secret = "asd2342"
    sleep_interval = 32

    config=<<EOF
server {
  web_interface {
    ip "#{ip}"
    port #{port}
    document_root "#{document_root}"
    base_url "#{base_url}"
    session_secret "#{session_secret}"
  }
}
EOF
    assert_nothing_raised { Mauve::ConfigurationBuilder.parse(config) }
 
    assert_equal(ip, Mauve::HTTPServer.instance.ip)
    assert_equal(port, Mauve::HTTPServer.instance.port)
    assert_equal(document_root, Mauve::HTTPServer.instance.document_root)
    assert_equal(base_url, Mauve::HTTPServer.instance.base_url)
    assert_equal(session_secret, Mauve::HTTPServer.instance.session_secret)
  end

  def test_pop3_server_params
    ip = "::1"
    port = 1101

    config=<<EOF
server {
  pop3_server {
    ip "#{ip}"
    port #{port}
  }
}
EOF
    assert_nothing_raised { Mauve::ConfigurationBuilder.parse(config) }

    assert_equal(ip, Mauve::Pop3Server.instance.ip)
    assert_equal(port, Mauve::Pop3Server.instance.port)

  end

  def test_listener_params
    ip = "::"
    port = 12341
    config=<<EOF

server {
  listener {
    ip "#{ip}"
    port #{port}
  }
}
EOF

    assert_nothing_raised { Mauve::ConfigurationBuilder.parse(config) }
    u = Mauve::UDPServer.instance
    assert_equal(IPAddr.new(ip), u.ip)
    assert_equal(port, u.port)
  end

  def test_notifier_params
    config=<<EOF
server {
  notifier {
  }
}
EOF

    assert_nothing_raised { Mauve::ConfigurationBuilder.parse(config) }
    n = Mauve::Notifier.instance
  end

  def test_processor_params
    transmission_cache_expire_time = 3120
    sleep_interval = 1235

    config=<<EOF
server {
  processor {
    transmission_cache_expire_time #{transmission_cache_expire_time}
  }
}
EOF

    assert_nothing_raised { Mauve::ConfigurationBuilder.parse(config) }
    pr = Mauve::Processor.instance    
    assert_equal(transmission_cache_expire_time, pr.transmission_cache_expire_time)
  end

end

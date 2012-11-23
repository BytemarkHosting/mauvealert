$:.unshift "../lib/"

require 'th_mauve'
require 'th_mauve_resolv'
require 'mauve/source_list'
require 'webmock'

class TcMauveSourceList < Mauve::UnitTest

  include Mauve
  include WebMock::API

  def setup
    super
    setup_database
    WebMock.disable_net_connect!
  end

  def teardown
    WebMock.reset!
    WebMock.allow_net_connect!
    teardown_database
    super
  end

  def test_hostname_match
    sl = SourceList.new("test")
    assert_equal("test", sl.label)

    list = %w(a.example.com b.example.com c.example.com)
    assert_nothing_raised{ sl += list }

    assert_equal(list, sl.list)

    assert( sl.includes?("a.example.com") )
    assert( !sl.includes?("d.example.com") )
  end

  def test_regex_match
    sl = SourceList.new("test")

    assert_nothing_raised{ sl += %w([a-c].example.com *.[d-f].example.com g.example.com) }

    %w(a.example.com www.f.example.com www.a.example.com g.example.com www.other.a.example.com).each do |h|
      assert( sl.includes?(h), "#{h} did not match")
    end

    %w(d.example.com a.example.com.other d.example.com).each do |h|
      assert( !sl.includes?(h), "#{h} matched when it shouldn't have")
    end
  end

  def test_ip_match
    sl = SourceList.new("test")

    assert_nothing_raised{ sl += %w(test-1.example.com 1.2.3.5 2001:1:2:3::5 1.2.4.0/24 2001:1:2:4::/64) }

    %w(1.2.3.4 2001:1:2:3::4 1.2.3.5 2001:1:2:3::5 test-2.example.com 1.2.4.23 2001:1:2:4::23 ).each do |h|
      assert( sl.includes?(h), "#{h} did not match")
    end

    %w(1.2.3.6 2001:1:2:3::6 test-3.example.com 1.2.5.23 2001:1:2:5::23 ).each do |h|
      assert( !sl.includes?(h), "#{h} matched when it shouldn't have")
    end
 
  end

  def test_uri_match
    sl = SourceList.new("test")

    assert_nothing_raised { sl += "test-1.example.com" }

    %w(https://www.example.com ftp://test-1.example.com http://1.2.3.4 https://[2001:1:2:3::4]).each do |uri|
      assert( sl.includes?(uri), "#{uri} did not match") 
    end

    %w(http://www.google.com ftp://www2.example.com).each do |uri|
      assert( !sl.includes?(uri), "#{uri} matched when it shouldn't have" )
    end
  end

  def test_ip_crossmatch
    sl = SourceList.new("test")
    assert_nothing_raised { sl += "test-1.example.com" }
    assert( sl.includes?("www.example.com"), "www.example.com not found in #{sl.list}" )

    sl = SourceList.new("test")
    assert_nothing_raised { sl += "2001::/3" }
    assert( sl.includes?("www2.example.com"), "www2.example.com not found in #{sl.list}" )
  end

  def test_ip_crossmatch_fail_when_minimal_dns_is_available
    Configuration.current.minimal_dns_lookups = true

    sl = SourceList.new("test")
    assert_nothing_raised { sl += "test-1.example.com" }
    assert( !sl.includes?("www.example.com"), "www.example.com not found in #{sl.list}" )

    sl = SourceList.new("test")
    assert_nothing_raised { sl += "2001::/3" }
    assert( !sl.includes?("www2.example.com"), "www2.example.com not found in #{sl.list}" )
  end

  def test_remote_source_list
    stub_request(:get, "http://localhost/network/monitor_ip/by_tag/Managed").
      to_return(:status => 200, :body => %w(1.2.3.4 1.2.3.5).join("\n"))

    sl = SourceList.new("test","http://localhost/network/monitor_ip/by_tag/Managed")

    assert( sl.includes?("1.2.3.4"), "1.2.3.4 not found in #{sl.list}" )
    assert( sl.includes?("test-1.example.com"), "test-1.example.com not found in #{sl.list}" )
  end

end


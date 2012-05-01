$:.unshift "../lib"

require 'th_mauve_resolv'
require 'test/unit'
require 'pp'
require 'timecop'
require 'mauve/sender'
require 'locale'
require 'iconv'


class TcMauveSender < Test::Unit::TestCase 
  include Mauve

  def setup
    Timecop.freeze(Time.local(2011,8,1,0,0,0,0))
  end

  def teardown
    Timecop.return
  end

  def test_sanitise
    Locale.clear
    Locale.current = "en_GB.ISO-8859-1"
    
    #
    # Set up a couple of crazy sources.
    #
    utf8_source = "Å ðîßtáñt plàñët"
    iso88591_source = Iconv.conv(Locale.current.charset, "UTF-8", utf8_source)

    #
    # Make sure our two sources are distinct
    #
    assert(iso88591_source != utf8_source)

    sender = Sender.new("test-1.example.com")
    update = Mauve::Proto::AlertUpdate.new
    update.source = iso88591_source
    update.replace = false

    alert = Mauve::Proto::Alert.new
    update.alert << alert
    
    alert_cleared = Mauve::Proto::Alert.new
    update.alert << alert_cleared
    alert_cleared.clear_time = Time.now.to_i
    
    #
    # Make sure the update has the correct source
    #
    assert_equal(iso88591_source, update.source)

    #
    # Sanitize
    #
    update = sender.sanitize(update)

    #
    # Now make sure the sanitization has changed it back to UTF-8
    #
    assert_equal(utf8_source, update.source)

    #
    # Now make sure the transmission time + id have been set
    #
    assert_equal(Time.now.to_i, update.transmission_time)
    assert_kind_of(Integer, update.transmission_id)

    #
    # Make sure that the alert has its raise time set by default
    #
    assert_equal(Time.now.to_i, alert.raise_time)
    assert_equal(0, alert_cleared.raise_time)
  end


end

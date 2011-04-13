# Mauve server tests - alerts and notification logic.  Define the basic workings
# so that we know what should happen when we send sequences of alerts at
# different times.
#
# These aren't really unit tests, just narrative specifications as to what
# should happen under what stimuli.  I suspect I will break these down into
# smaller units if things break under otherwise difficult conditions.
#

$: << __FILE__.split("/")[0..-2].join("/")
require 'test/unit'
require 'mauve_test_helper'
require 'mauve_time'

class AlertAndNotificationLogic < Test::Unit::TestCase
  include MauveTestHelper
    
  def configuration_template
    <<-TEMPLATE
    # This is the head of all the configuration files.  Filenames are relative
    # to the cwd, which is assumed to be a fleeting test directory.

    server {
      ip "127.0.0.1"
      port #{@port_alerts ||= 44444}
      log_file ENV['TEST_LOG'] ? STDOUT : "#{dir}/log"
      log_level 0
      database "sqlite3:///#{dir}/mauve_test.db"
      transmission_id_expire_time 600

      # doesn't restart nicely at the moment      
      #web_interface {
      #  port #{@port_web ||= 44444}
      #}
    }

    #
    # All notifications are sent to files which we can open up and check during
    # our tests.  Network delivery is not tested in this script.
    #

    notification_method("xmpp") {
      deliver_to_queue AlertAndNotificationLogic::Notifications
      deliver_to_file "#{dir}/xmpp.txt"
      disable_normal_delivery!

      jid "mauveserv@chat.bytemark.co.uk"
      password "foo"
    }

    notification_method("email") {
      deliver_to_queue AlertAndNotificationLogic::Notifications
      deliver_to_file "#{dir}/email.txt"
      disable_normal_delivery!
      
      # add in SMTP server, username, password etc.
      # default to sending through localhost
      from "matthew@bytemark.co.uk"
      server "bytemail.bytemark.co.uk"
      subject_prefix "[Bytemark alerts] "
      
    }

    notification_method("sms") {
      provider "AQL"
      deliver_to_queue AlertAndNotificationLogic::Notifications
      deliver_to_file "#{dir}/sms.txt"
      disable_normal_delivery!
      
      username "x"
      password "x"
      from "01904890890"
      max_messages_per_alert 3
    }

    # a person common to all our tests

    person("joe_bloggs") {
      urgent { sms("12345") }
      normal { email("12345@joe_bloggs.email") }
      low { xmpp("12345@joe_bloggs.xmpp") }
    }
    
    person("jimmy_junior") {
      urgent { sms("66666") }
      normal { email("jimmy@junior.email") }
      low { email("jimmy@junior.email") }
    }

    alert_group {
      includes { source == "rare-and-important" }
      acknowledgement_time 60.minutes
      level URGENT
      
      notify("joe_bloggs") { every 10.minutes }
    }
    
    alert_group {
      includes { source == "noisy-and-annoying" || alert_id == "whine" }
      acknowledgement_time 24.hours
      level LOW
      
      notify("jimmy_junior") { every 2.hours }
      notify("joe_bloggs") { 
        every 30.minutes 
        during {
          unacknowledged 6.hours
        }
      }
    }
    
    alert_group {
      includes { source == "can-wait-until-monday" }
      level NORMAL
      
      notify("jimmy_junior") {
        every 30.minutes
        during { days_in_week(1..5) && hours_in_day(9..5) }
      }
      notify("joe_bloggs") {
        every 2.hours
        during { days_in_week(1..5) && hours_in_day(9..5) }
      }
    }

    # catch-all
    alert_group {
      acknowledgement_time 1.minute
      level NORMAL
      
      notify("joe_bloggs") { every 1.hour }
    }
    TEMPLATE
  end
  
  def setup
    start_server(configuration_template)
  end
  
  def teardown
    stop_server
    # no tests should leave notifications on the stack
    assert_no_notification
  end
  
  # Raise one alert, check representation in database, and that alert is 
  # received as expected.
  #
  def test_basic_fields_are_recognised
    mauvesend("-o my_source -i alert1 -s \"alert1 summary\" -d \"alert1 detail\" -u \"alert1 subject\"")

    assert_not_nil(alert = Alert.first)
    assert_equal("my_source", alert.source)
    assert_equal("alert1", alert.alert_id)
    assert_equal("alert1 summary", alert.summary)
    assert_equal("alert1 detail", alert.detail)
    assert_equal("alert1 subject", alert.subject)
    assert(alert.raised?)
    assert(!alert.cleared?)
    assert(!alert.acknowledged?)
    
    with_next_notification do |destination, this_alert, other_alerts|    
      assert_equal("12345@joe_bloggs.email", destination)
      assert_equal(Alert.first, this_alert)
      assert_equal([Alert.first], other_alerts)
    end
    
  end
  
  # Check that a simple automatic raise, acknowledge & auto-clear request 
  # work properly.
  #
  def test_auto_raise_and_clear
    # Raise the alert, wait for it to be processed
    mauvesend("-o my_source -i alert1 -s \"alert1 summary\" -d \"alert1 detail\" -u \"alert1 subject\" -r +5m -c +10m")
    
    # Check internal state
    #
    assert(!Alert.first.raised?, "Auto-raising alert raised early")
    assert(!Alert.first.cleared?, "Auto-clearing alert cleared early")
    assert(!Alert.first.acknowledged?, "Alert acknowledged when I didn't expect it")
    
    # We asked for it to be raised in 5 minutes, so no alert yet...
    #
    assert_no_notification

    # Push forward to when the alert should be raised, check it has been
    #
    Time.advance(5.minutes)    
    assert(Alert.first.raised?, "#{Alert.first.inspect} should be raised by now")
    assert(!Alert.first.cleared?, "#{Alert.first.inspect} should not be cleared")
    
    # Check that we have a notification
    #
    with_next_notification do |destination, this_alert, other_alerts|
      assert_equal("12345@joe_bloggs.email", destination)
      assert_equal(Alert.first, this_alert)
      assert_equal('raised', this_alert.update_type)
    end
    
    # Simulate manual acknowledgement
    #
    Alert.first.acknowledge!(Configuration.current.people["joe_bloggs"])
    Timers.restart_and_then_wait_until_idle    
    assert(Alert.first.acknowledged?, "Acknowledgement didn't work")

    # Check that the acknowledgement has caused a notification
    #
    with_next_notification do |destination, this_alert, other_alerts|
      assert_equal("12345@joe_bloggs.email", destination)
      assert_equal(Alert.first, this_alert)
      assert_equal('acknowledged', this_alert.update_type, this_alert.inspect)
    end
    assert(Alert.first.acknowledged?)
    assert(Alert.first.raised?)
    assert(!Alert.first.cleared?)
    
    # Now with the config set to un-acknowledge alerts after only 1 minute,
    # try winding time on and check that this happens.
    #
    Time.advance(2.minutes)
    with_next_notification do |destination, this_alert, other_alerts|
      assert_equal("12345@joe_bloggs.email", destination)
      assert_equal(Alert.first, this_alert)
      assert_equal('raised', this_alert.update_type, this_alert.inspect)
    end
    
    # Check that auto-clearing works four minutes later
    #
    Time.advance(5.minutes)
    assert(Alert.first.cleared?)
    assert(!Alert.first.raised?)

    # Finally check for a notification that auto-clearing has happened
    #
    with_next_notification do |destination, this_alert, other_alerts| 
      assert_equal("12345@joe_bloggs.email", destination)
      assert_equal(Alert.first, this_alert)
      assert_equal('cleared', this_alert.update_type, this_alert.inspect)
    end
    
    # And see that no further reminders are sent a while later
    Time.advance(1.day)
    assert_no_notification
  end
  
  def test_one_alert_changes_from_outside
    # Raise our test alert, wait for it to be processed
    mauvesend("-o my_source -i alert1 -s \"alert1 summary\" -d \"alert1 detail\" -u \"alert1 subject\"")
    
    # Check internal representation, external notification
    # 
    assert(Alert.first.raised?)
    assert(!Alert.first.cleared?)
    with_next_notification do |destination, this_alert, other_alerts|      
      assert_equal('raised', this_alert.update_type, this_alert.inspect)
    end
    
    # Check we get reminders every hour, and no more
    #
    12.times do
      Time.advance(1.hour)
      with_next_notification do |destination, this_alert, other_alerts|      
        assert_equal('raised', this_alert.update_type, this_alert.inspect)
      end
      assert_no_notification 
    end
    
    # Clear the alert, wait for it to be processed
    mauvesend("-o my_source -i alert1 -c now")
    assert(!Alert.first.raised?)
    assert(Alert.first.cleared?)
    with_next_notification do |destination, this_alert, other_alerts|      
      assert_equal('cleared', this_alert.update_type, this_alert.inspect)
    end
    
    # Check we can raise the same alert again
    Time.advance(1.minute)
    mauvesend("-o my_source -i alert1 -s \"alert1 summary\" -d \"alert1 detail\" -u \"alert1 subject\" -r now")
    assert(Alert.first.raised?, Alert.first.inspect)
    assert(!Alert.first.cleared?, Alert.first.inspect)
    with_next_notification do |destination, this_alert, other_alerts|      
      assert_equal('raised', this_alert.update_type, this_alert.inspect)
    end
  end
  
  def test_alert_groups
    # check that this alert is reminded more often than normal
    mauvesend("-o rare-and-important -i alert1 -s \"rare and important alert\"")
    assert(Alert.first.raised?)
    assert(!Alert.first.cleared?)
    
    10.times do
      with_next_notification do |destination, this_alert, other_alerts|
        assert_equal('raised', this_alert.update_type, this_alert.inspect)
        assert_equal('12345', destination)
        Time.advance(10.minutes)
      end
    end
    discard_next_notification
  end
  
  def test_future_raising
    mauvesend("-i heartbeat -c now -r +10m -s \"raise in the future\"")
    assert(!Alert.first.raised?)
    assert(Alert.first.cleared?)
    assert_no_notification
    
    # Check the future alert goes off
    #
    Time.advance(10.minutes)
    assert(Alert.first.raised?)
    assert(!Alert.first.cleared?)
    with_next_notification do |destination, this_alert, other_alerts|
      assert_equal('raised', this_alert.update_type, this_alert.inspect)
    end
    
    # Check that a repeat of the "heartbeat" update clears it, and we get
    # a notification.
    #
    mauvesend("-i heartbeat -c now -r +10m -s \"raise in the future\"")
    assert(!Alert.first.raised?)
    assert(Alert.first.cleared?)
    with_next_notification do |destination, this_alert, other_alerts|
      assert_equal('cleared', this_alert.update_type, this_alert.inspect)
    end
    
    # Check that a re-send of the same clear alert doesn't send another 
    # notification
    #
    Time.advance(1.minute)
    mauvesend("-i heartbeat -c now -r +10m -s \"raise in the future\"")
    assert(!Alert.first.raised?)
    assert(Alert.first.cleared?)
    assert_no_notification
    
    # Check that a skewed resend doesn't confuse it
    #
    mauvesend("-i heartbeat -c +1m -r +11m -s \"raise in the future\"")
    assert(!Alert.first.raised?)
    assert(Alert.first.cleared?)
    Time.advance(1.minute)
    assert(!Alert.first.raised?)
    assert(Alert.first.cleared?)
    assert_no_notification
  end
  
  # Make sure that using the "replace all flag" works as expected.
  #
  def test_replace_flag
    mauvesend("-p")
    #mauvesend("-p")
    assert_no_notification
    
    mauvesend("-i test1 -s\"\test1\"")
    assert(Alert.first.raised?)
    with_next_notification do |destination, this_alert, other_alerts|
      assert_equal('raised', this_alert.update_type, this_alert.inspect)
    end
    assert_no_notification
    
    mauvesend("-p")
    #mauvesend("-p")
    with_next_notification do |destination, this_alert, other_alerts|
      assert_equal('cleared', this_alert.update_type, this_alert.inspect)
    end
    assert_no_notification
  end
  
  def test_earliest_date
    alert = Alert.create!(
      :alert_id => "test_id",
      :source => "test1",
      :subject => "test subject",
      :summary => "test summary",
      :raised_at => nil,
      :will_raise_at => Time.now + 60,
      :will_clear_at => Time.now + 120,
      :update_type => "cleared",
      :updated_at => Time.now
    )
    assert(alert)
    
    assert(AlertEarliestDate.first.alert == alert)
  end
  
end





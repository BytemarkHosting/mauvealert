$:.unshift "../lib"

require 'th_mauve'
require 'mauve/calendar_interface'
require 'mauve/configuration_builder'
require 'mauve/configuration'
require 'webmock'
#
# Ugh webmock is annoying.
WebMock.allow_net_connect!

class TcMauveCalendarInterface < Mauve::UnitTest 

  include WebMock::API
  include Mauve

  def setup
    WebMock.disable_net_connect!
    super
  end

  def teardown
    WebMock.reset!
    WebMock.allow_net_connect!
    super
  end

  def test_get_attendees
    attendees = %w(test1 test2)
    stub_request(:get, "http://localhost/calendar/api/attendees/support_shift/2011-08-01T00:00:00").
      to_return(:status => 200, :body => YAML.dump(attendees))

    config =<<EOF
bytemark_calendar_url "http://localhost/calendar"
EOF

    Configuration.current = ConfigurationBuilder.parse(config)

    assert_equal(attendees, CalendarInterface.get_attendees("support_shift"))
  end

  def test_is_user_on_holiday?
    attendees = %w(test1 test2)
    stub_request(:get, "http://localhost/calendar/api/attendees/staff_holiday/2011-08-01T00:00:00").
      to_return(:status => 200, :body => YAML.dump(attendees))


    config =<<EOF
bytemark_calendar_url "http://localhost/calendar"
EOF

    Configuration.current = ConfigurationBuilder.parse(config)

    assert(CalendarInterface.is_user_on_holiday?("test1"))
    assert(!CalendarInterface.is_user_on_holiday?("test3"))
  end

  def test_is_user_off_sick?
    attendees = %w(test1 test2)
    stub_request(:get, "http://localhost/calendar/api/attendees/sick_period/2011-08-01T00:00:00").
      to_return(:status => 200, :body => YAML.dump(attendees))

    config =<<EOF
bytemark_calendar_url "http://localhost/calendar"
EOF

    Configuration.current = ConfigurationBuilder.parse(config)

    assert(CalendarInterface.is_user_off_sick?("test1"))
    assert(!CalendarInterface.is_user_off_sick?("test3"))
  end

end






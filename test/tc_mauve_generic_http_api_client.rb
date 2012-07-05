$:.unshift "../lib"

require 'th_mauve'
require 'mauve/calendar_interface'
require 'mauve/configuration_builder'
require 'mauve/configuration'
require 'webmock'

class TcMauveGenericApiClient < Mauve::UnitTest 

  include WebMock::API
  include Mauve
  include Mauve::GenericHttpApiClient

  def setup
    WebMock.disable_net_connect!
    super
  end

  def teardown
    WebMock.reset!
    WebMock.allow_net_connect!
    super
  end

  def test_do_get
    url = "http://localhost/"

    #
    # This sets up two redirects, followed by the answer (below) 
    #
    2.times do |x|
      next_url = url + "#{x}/"
      stub_request(:get, url).
        to_return(:status => 301, :body => nil, :headers => {:location => next_url})
      url = next_url
    end

    #
    # And finally the answer.
    #
    stub_request(:get, url).
      to_return(:status => 200, :body => "OK!", :headers => {})

    #
    # Now do_get should return "OK!" when the maximum number of redirects is set to two.
    #
    result = nil
    assert_nothing_raised{ result = do_get("http://localhost/", 2) }
    assert_equal("OK!",result)

    #
    # do_get should return nil when the maximum number of redirects is set to two.
    #
    assert_nothing_raised{ result = do_get( "http://localhost/", 1) }
    assert_nil(result)

    #
    # Pop the warning about the redirect off the end of the log.
    #
    logger_pop
  end
  
  def test_do_get_with_cache
    url = "http://localhost/"

    #
    # This stubs the request to give out the time
    #
    stub_request(:get, url).
      to_return( lambda{ {:status => 200, :body => YAML.dump(Time.now), :headers => {}} } )

    #
    # This reponse should not be cached, the cache-until paramter is "now"
    #
    assert_equal(YAML.dump(Time.now), do_get_with_cache( url, Time.now))

    #
    # Since the last request wasn't cached, the next one should give back
    # "now", and should be cached for the next 10 seconds.
    #
    Timecop.freeze(Time.now + 5)
    assert_equal(YAML.dump(Time.now), do_get_with_cache( url, Time.now + 10))

    #
    # This should have been cached from the last query.
    #
    Timecop.freeze(Time.now + 5)
    assert_equal(YAML.dump(Time.now - 5), do_get_with_cache( url, Time.now + 10))

    #
    # Finally, this should now have expired from the cache.
    #
    Timecop.freeze(Time.now + 5)
    assert_equal(YAML.dump(Time.now), do_get_with_cache( url,  Time.now + 10))

    Timecop.freeze(Time.now + 50)
    cache = clean_cache
    assert(cache.empty?)
  end


end






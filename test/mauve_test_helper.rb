require 'tmpdir'
require 'thread'
require 'timeout'
require 'mauve/configuration'

Thread.abort_on_exception = true

module MauveTestHelper
  include Mauve
  Notifications = Queue.new
  
  # Returns the base directory for temporary files for this test instance
  #
  def dir
    if !@test_dir
      now = ::Time.now
      base=Dir.tmpdir+"/mauve_test"
      Dir.mkdir(base) unless File.directory?(base)
      base=base+"/#{$$}"
      Dir.mkdir(base) unless File.directory?(base)
      Dir.mkdir(@test_dir="#{base}/#{name}")
    end
    @test_dir
  end
  
  # Starts the Mauve server with a configuration supplied as a string.
  #
  def start_server(config)
    @here = File.expand_path(__FILE__).split("/")[0..-2].join("/") + "/.."
    File.open("#{dir}/config_file", "w") { |fh| fh.write(config) }
    Notifications.clear
    
    Configuration.current = ConfigurationBuilder.load("#{dir}/config_file")
    Time.reset_to_midnight
    @thread = Thread.new do
      begin
        Configuration.current.server.run
      rescue Interrupt
        Configuration.current.close
      end
    end
    # avoids races if we try to shut down too quickly
    Configuration.current.server.sleep_until_ready
    Log.info "TEST RUN STARTED: #{name}"
  end
  
  # Stops the Mauve server, should reset it ready to start again within the
  # same process.
  #
  def stop_server
    @thread.raise(Interrupt.new)
    @thread.join
  end
  
  # Send an alert to the server, return when the server process has definitely
  # processed it (or die after 2s).
  #
  def mauvesend(cmd)
    Configuration.current.server.sleep_until_ready
    output = `TEST_TIME=#{Time.now.to_i} #{@here}/mauve_starter.rb #{@here}/bin/mauvesend -v 127.0.0.1:44444 #{cmd} 2>&1`
    status = $?.exitstatus
    raise "Exit #{status} from command: '#{output}'" unless status == 0
    raise "mauvesend did not return an integer" unless output.to_i > 0
    begin
      timeout(2) { Configuration.current.server.sleep_until_transmission_id_received(output.to_i) }
    rescue Timeout::Error
      flunk("Did not receive transmission id '#{output}'")
    end
  end
  
  # Assuming the test configuration contains a notification method with 
  # "deliver_to_queue TestClass::Notifications", this helper will return the next
  # alert notification by that method as a triplet:
  #
  #   [destination, alert, other_alerts]
  #
  # e.g. destination will be an email address, or phone number, just
  # as in the configuration file.  alert will be the subject of this 
  # alert, and other_alerts will be the other notifications that
  # are relevant for this person at this time.
  #
  # The test will fail after 2s if no alert is received.
  #
  def with_next_notification
    Timers.restart_and_then_wait_until_idle
    flunk("Nothing on Notifications queue when I expected one") if Notifications.empty?
    yield(*Notifications.pop)
  end
  
  def discard_next_notification
    with_next_notification { }
  end
  
  # The reverse of next_alert, the test fails if an alert is received
  # within 2s.
  # 
  def assert_no_notification
    Timers.restart_and_then_wait_until_idle
    flunk("#{Notifications.pop.inspect} on Notifications queue when I expected nothing") unless 
      Notifications.empty?
    true
  end
end


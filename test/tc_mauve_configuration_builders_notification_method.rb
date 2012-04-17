$:.unshift "../lib/"

require 'th_mauve'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders/notification_method'

class TcMauveConfigurationBuildersNotificationMethod < Mauve::UnitTest

  def test_debug_methods
    config =<<EOF
notification_method("email") {
  debug!
  disable_normal_delivery!
  deliver_to_queue []
}
EOF
    x = nil
    assert_nothing_raised { x = Mauve::ConfigurationBuilder.parse(config) }

    y = x.notification_methods["email"]

    # TODO test delivery 
  end

end

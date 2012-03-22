
%w(. ..).each do |path|
  libdir = File.join(path,"lib")
  $:.unshift libdir if File.directory?(libdir)
end

require 'pp'
require 'test/unit'
require 'th_mauve'

%w(
tc_mauve_alert_changed.rb
tc_mauve_alert_group.rb
tc_mauve_alert.rb
tc_mauve_configuration_builder.rb
tc_mauve_configuration_builders_alert_group.rb
tc_mauve_configuration_builders_logger.rb
tc_mauve_configuration_builders_notification_method.rb
tc_mauve_configuration_builders_person.rb
tc_mauve_configuration_builders_server.rb
tc_mauve_history.rb
tc_mauve_notification.rb
tc_mauve_people_list.rb
tc_mauve_person.rb
tc_mauve_source_list.rb
tc_mauve_time.rb
tc_mauve_web_interface.rb
).each do |s|
  require s
end



%w(. ..).each do |path|
  libdir = File.join(path,"lib")
  $:.unshift libdir if File.directory?(libdir)
end

require 'test/unit'

%w(
tc_mauve_configuration_builder.rb
tc_mauve_configuration_builders_alert_group.rb
tc_mauve_configuration_builders_logger.rb
tc_mauve_configuration_builders_notification_method.rb
tc_mauve_configuration_builders_person.rb
tc_mauve_configuration_builders_server.rb
tc_mauve_source_list.rb
tc_mauve_people_list.rb
tc_mauve_alert.rb
tc_mauve_alert_group.rb
).each do |s|
  require s
end


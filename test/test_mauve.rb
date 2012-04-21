
%w(. ..).each do |path|
  libdir = File.join(path,"lib")
  $:.unshift libdir if File.directory?(libdir)
end

require 'pp'
require 'test/unit'
require 'th_mauve'

%w(. test).each do |dir|
Dir.glob(File.join(dir,"tc_*.rb")).each do |s|
  require s
end
end


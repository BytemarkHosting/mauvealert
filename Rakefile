require 'rake/testtask'

task :console do
  $:.push("lib")
  require 'irb'
  require 'irb/completion'
  require 'mauve/server'
  ARGV.clear
  IRB.start
end

Rake::TestTask.new do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/tc_*']
  t.verbose=true
end

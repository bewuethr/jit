require "rake/testtask"
require "standard/rake"

Rake::TestTask.new do |task|
  task.pattern = "test/**/*_test.rb"
end

desc "Run all tasks"
task all: %w[test standard]

task default: :test

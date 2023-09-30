require "rake/testtask"

Rake::TestTask.new do |task|
  task.pattern = "test/**/*_test.rb"
end

desc "Run Standard Ruby"
task :lint do
  `standardrb`
end

desc "Run all tasks"
task all: %w[test lint]

task default: :test

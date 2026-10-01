# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "lib" << "test"
  task.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

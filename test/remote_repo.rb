require_relative "command_helper"

class RemoteRepo
  include CommandHelper

  def initialize(name) = @name = name

  def repo_path
    Pathname.new(File.expand_path("../test-repo-#{@name}", __FILE__))
  end
end

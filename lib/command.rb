require_relative "command/add"
require_relative "command/branch"
require_relative "command/checkout"
require_relative "command/commit"
require_relative "command/diff"
require_relative "command/init"
require_relative "command/log"
require_relative "command/merge"
require_relative "command/rm"
require_relative "command/status"

module Command
  Unknown = Class.new(StandardError)

  COMMANDS = {
    "add" => Add,
    "branch" => Branch,
    "checkout" => Checkout,
    "commit" => Commit,
    "diff" => Diff,
    "init" => Init,
    "log" => Log,
    "merge" => Merge,
    "rm" => Rm,
    "status" => Status
  }

  def self.execute(dir, env, argv, stdin, stdout, stderr)
    name = argv.first
    args = argv.drop(1)

    unless COMMANDS.has_key?(name)
      raise Unknown, "'#{name}' is not a jit command."
    end

    command_class = COMMANDS[name]
    command = command_class.new(dir, env, args, stdin, stdout, stderr)

    command.execute
    command
  end
end

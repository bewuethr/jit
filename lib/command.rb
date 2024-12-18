require_relative "command/add"
require_relative "command/branch"
require_relative "command/checkout"
require_relative "command/cherry_pick"
require_relative "command/commit"
require_relative "command/config"
require_relative "command/diff"
require_relative "command/fetch"
require_relative "command/init"
require_relative "command/log"
require_relative "command/merge"
require_relative "command/push"
require_relative "command/receive_pack"
require_relative "command/remote"
require_relative "command/reset"
require_relative "command/rev_list"
require_relative "command/revert"
require_relative "command/rm"
require_relative "command/status"
require_relative "command/upload_pack"

module Command
  Unknown = Class.new(StandardError)

  COMMANDS = {
    "add" => Add,
    "branch" => Branch,
    "checkout" => Checkout,
    "cherry-pick" => CherryPick,
    "commit" => Commit,
    "config" => Config,
    "diff" => Diff,
    "fetch" => Fetch,
    "init" => Init,
    "log" => Log,
    "merge" => Merge,
    "push" => Push,
    "receive-pack" => ReceivePack,
    "remote" => Remote,
    "reset" => Reset,
    "rev-list" => RevList,
    "revert" => Revert,
    "rm" => Rm,
    "status" => Status,
    "upload-pack" => UploadPack
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

require "pathname"

require_relative "base"
require_relative "../repository"

module Command
  class Init < Base
    DEFAULT_BRANCH = "main"

    def run
      path = @args.fetch(0, @dir)

      root_path = expanded_pathname(path)
      git_path = root_path.join(".git")

      ["objects", "refs/heads"].each do |dir|
        FileUtils.mkdir_p(git_path.join(dir))
      rescue Errno::EACCES => error
        @stderr.puts "fatal: #{error.message}"
        exit 1
      end

      refs = Refs.new(git_path)
      path = File.join("refs", "heads", DEFAULT_BRANCH)
      refs.update_head("ref: #{path}")

      puts "Initialized empty Jit repository in #{git_path}"
      exit 0
    end
  end
end

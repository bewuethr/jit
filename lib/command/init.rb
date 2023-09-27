require "pathname"
require_relative "../repository"

module Command
  class Init
    def run
      path = ARGV.fetch(0, Dir.getwd)

      root_path = Pathname.new(File.expand_path(path))
      git_path = root_path.join(".git")

      ["objects", "refs"].each do |dir|
        FileUtils.mkdir_p(git_path.join(dir))
      rescue Errno::EACCES => error
        warn "fatal: #{error.message}"
        exit 1
      end

      puts "Initialized empty Jit repository in #{git_path}"
      exit 0
    end
  end
end

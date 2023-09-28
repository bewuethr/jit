module Command
  class Base
    attr_reader :status

    def exit(status = 0)
      @status = status
      throw :exit
    end

    def initialize(dir, env, args, stdin, stdout, stderr)
      @dir = dir
      @env = env
      @args = args
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
    end

    def execute
      catch(:exit) { run }
    end

    def expanded_pathname(path)
      Pathname.new(File.expand_path(path, @dir))
    end

    def puts(string)
      @stdout.puts(string)
    end
  end
end

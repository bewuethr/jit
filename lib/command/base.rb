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
      @isatty = @stdout.isatty
    end

    def repo
      @repo ||= Repository.new(Pathname.new(@dir).join(".git"))
    end

    def execute
      catch(:exit) { run }

      if defined? @pager
        @stdout.close_write
        @pager.wait
      end
    end

    def expanded_pathname(path) = Pathname.new(File.expand_path(path, @dir))

    def puts(string)
      @stdout.puts(string)
    rescue Errno::EPIPE
      exit 0
    end

    def fmt(style, string) = @isatty ? Color.format(style, string) : string

    def setup_pager
      return if defined? @pager
      return unless @isatty

      @pager = Pager.new(@env, @stdout, @stderr)
      @stdout = @pager.input
    end
  end
end

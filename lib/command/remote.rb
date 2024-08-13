require_relative "base"

module Command
  class Remote < Base
    def define_options
      @parser.on("-v", "--verbose") { @options[:verbose] = true }

      @options[:tracked] = []
      @parser.on("-t <branch>") { @options[:tracked].push(_1) }
    end

    def run
      case @args.shift
      when "add" then add_remote
      when "remove" then remove_remote
      else list_remotes
      end
    end

    private def add_remote
      name, url = @args[0], @args[1]
      repo.remotes.add(name, url, @options[:tracked])
      exit 0
    rescue Remotes::InvalidRemote => error
      @stderr.puts "fatal: #{error.message}"
      exit 128
    end

    private def remove_remote
      repo.remotes.remove(@args[0])
      exit 0
    rescue Remotes::InvalidRemote => error
      @stderr.puts "fatal: #{error.message}"
      exit 128
    end

    private def list_remotes
      repo.remotes.list_remotes.each { list_remote(_1) }
      exit 0
    end

    private def list_remote(name)
      return puts name unless @options[:verbose]

      remote = repo.remotes.get(name)

      puts "#{name}\t#{remote.fetch_url} (fetch)"
      puts "#{name}\t#{remote.push_url} (push)"
    end
  end
end

require_relative "base"

module Command
  class Config < Base
    def define_options
      @parser.on("--local") { @options[:file] = :local }
      @parser.on("--global") { @options[:file] = :global }
      @parser.on("--system") { @options[:file] = :system }

      @parser.on("-f <config-file>", "--file=<config-file>") { options[:file] = _1 }

      @parser.on("--add <name>") { @options[:add] = _1 }
      @parser.on("--replace-all <name>") { @options[:replace] = _1 }
      @parser.on("--get-all <name>") { @options[:get_all] = _1 }
      @parser.on("--unset <name>") { @options[:unset] = _1 }
      @parser.on("--unset-all <name>") { @options[:unset_all] = _1 }

      @parser.on("--remove-section <name>") { @options[:remove_section] = _1 }
    end

    def run
      add_variable if @options[:add]
      replace_variable if @options[:replace]
      get_all_values if @options[:get_all]
      unset_single if @options[:unset]
      unset_all if @options[:unset_all]
      remove_section if @options[:remove_section]

      key, value = parse_key(@args[0]), @args[1]

      if value
        edit_config { _1.set(key, value) }
      else
        read_config { [*_1.get(key)] }
      end
    rescue ::Config::ParseError => error
      @stderr.puts "error: #{error.message}"
      exit 3
    end

    private def add_variable
      key = parse_key(@options[:add])
      edit_config { _1.add(key, @args[0]) }
    end

    private def replace_variable
      key = parse_key(@options[:replace])
      edit_config { _1.replace_all(key, @args[0]) }
    end

    private def unset_single
      key = parse_key(@options[:unset])
      edit_config { _1.unset(key) }
    end

    private def unset_all
      key = parse_key(@options[:unset_all])
      edit_config { _1.unset_all(key) }
    end

    private def remove_section
      key = @options[:remove_section].split(".", 2)
      edit_config { _1.remove_section(key) }
    end

    private def get_all_values
      key = parse_key(@options[:get_all])
      read_config { _1.get_all(key) }
    end

    private def read_config
      config = repo.config
      config = config.file(@options[:file]) if @options[:file]

      config.open
      values = yield config

      exit 1 if values.empty?

      values.each { puts _1 }
      exit 0
    end

    private def edit_config
      config = repo.config.file(@options.fetch(:file, :local))
      config.open_for_update
      yield config
      config.save

      exit 0
    rescue ::Config::Conflict => error
      @stderr.puts "error: #{error.message}"
      exit 5
    end

    private def parse_key(name)
      section, *subsection, var = name.split(".")

      unless var
        @stderr.puts "error: key does not contain a section: #{name}"
        exit 2
      end

      unless ::Config.valid_key?([section, var])
        @stderr.puts "error: invalid key: #{name}"
        exit 1
      end

      if subsection.empty?
        [section, var]
      else
        [section, subsection.join("."), var]
      end
    end
  end
end

require "shellwords"

class Editor
  DEFAULT_EDITOR = "vi"

  def self.edit(path, command)
    editor = Editor.new(path, command)
    yield editor
    editor.edit_file
  end

  def initialize(path, command)
    @path = path
    @command = command || DEFAULT_EDITOR
    @closed = false
  end

  def puts(string)
    return if @closed
    file.puts(string)
  end

  def note(string)
    return if @closed
    string.each_line { file.puts("# #{_1}") }
  end

  def close = @closed = true

  def edit_file
    file.close
    editor_argv = Shellwords.shellsplit(@command) + [@path.to_s]

    unless @closed || system(*editor_argv)
      raise "There was a problem with the editor '#{@command}'."
    end

    remove_notes(File.read(@path))
  end

  private def file
    flags = File::WRONLY | File::CREAT | File::TRUNC
    @file ||= File.open(@path, flags)
  end

  private def remove_notes(string)
    lines = string.lines.reject { _1.start_with?("#") }

    if lines.all? { /^\s*$/ =~ _1 }
      nil
    else
      "#{lines.join("").strip}\n"
    end
  end
end

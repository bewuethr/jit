class Repository
  class PendingCommit
    Error = Class.new(StandardError)

    attr_reader :message_path

    def initialize(pathname)
      @head_path = pathname.join("MERGE_HEAD")
      @message_path = pathname.join("MERGE_MSG")
    end

    def start(oid)
      flags = File::WRONLY | File::CREAT | File::EXCL
      File.open(@head_path, flags) { _1.puts(oid) }
    end

    def clear(type = :merge)
      File.unlink(@head_path)
      File.unlink(@message_path)
    rescue Errno::ENOENT
      name = @head_path.basename
      raise Error, "There is no merge to abort (#{name} missing)."
    end

    def in_progress? = File.file?(@head_path)

    def merge_oid
      File.read(@head_path).strip
    rescue Errno::ENOENT
      name = @head_path.basename
      raise Error, "There is no merge in progress (#{name} missing)."
    end

    def merge_message = File.read(@message_path)
  end
end

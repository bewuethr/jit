require_relative "../../repository"
require_relative "../../remotes/protocol"

module Command
  module RemoteAgent
    ZERO_OID = "0" * 40

    def accept_client(name, capabilities = [])
      @conn = Remotes::Protocol.new(name, @stdin, @stdout, capabilities)
    end

    def send_references
      refs = repo.refs.list_all_refs
      sent = false

      refs.sort_by(&:path).each do |symref|
        next unless (oid = symref.read_oid)
        @conn.send_packet("#{oid.downcase} #{symref.path}")
        sent = true
      end

      @conn.send_packet("#{ZERO_OID} capabilities^{}") unless sent
      @conn.send_packet(nil)
    end

    def repo = @repo ||= Repository.new(detect_git_dir)

    def detect_git_dir
      pathname = expanded_pathname(@args[0])
      dirs = pathname.ascend.flat_map { [_1, _1.join(".git")] }
      dirs.find { git_repository?(_1) }
    end

    def git_repository?(dirname)
      File.file?(dirname.join("HEAD")) &&
        File.directory?(dirname.join("objects")) &&
        File.directory?(dirname.join("refs"))
    end
  end
end

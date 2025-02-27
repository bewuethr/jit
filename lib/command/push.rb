require_relative "base"
require_relative "shared/fast_forward"
require_relative "shared/remote_client"
require_relative "shared/send_objects"
require_relative "../remotes"
require_relative "../revision"

module Command
  class Push < Base
    include FastForward
    include RemoteClient
    include SendObjects

    CAPABILITIES = ["report-status"]
    RECEIVE_PACK = "git-receive-pack"
    UNPACK_LINE = /^unpack (.+)$/
    UPDATE_LINE = /^(ok|ng) (\S+)(.*)$/

    def define_options
      @parser.on("-f", "--force") { @options[:force] = true }
      @parser.on("--receive-pack=<receive-pack>") { @options[:receiver] = _1 }
    end

    def run
      configure
      start_agent("push", @receiver, @push_url, CAPABILITIES)

      recv_references
      send_update_requests
      send_objects
      print_summary
      recv_report_status

      exit(@errors.empty? ? 0 : 1)
    end

    private def configure
      current_branch = repo.refs.current_ref.short_name
      branch_remote = repo.config.get(["branch", current_branch, "remote"])
      branch_merge = repo.config.get(["branch", current_branch, "merge"])

      name = @args.fetch(0, branch_remote || Remotes::DEFAULT_REMOTE)
      remote = repo.remotes.get(name)

      @push_url = remote&.push_url || @args[0]
      @fetch_specs = remote&.fetch_specs || []
      @receiver = @options[:receiver] || remote&.receiver || RECEIVE_PACK

      if @args.size > 1
        @push_specs = @args.drop(1)
      elsif branch_merge
        spec = Remotes::Refspec.new(current_branch, branch_merge, false)
        @push_specs = [spec.to_s]
      else
        @push_specs = remote&.push_specs
      end
    end

    private def send_update_requests
      @updates = {}
      @errors = []

      local_refs = repo.refs.list_all_refs.map(&:path).sort
      targets = Remotes::Refspec.expand(@push_specs, local_refs)

      targets.each do |target, (source, forced)|
        select_update(target, source, forced)
      end

      @updates.each { |ref, (*, old, new)| send_update(ref, old, new) }
      @conn.send_packet(nil)
    end

    private def select_update(target, source, forced)
      return select_deletion(target) unless source

      old_oid = @remote_refs[target]
      new_oid = Revision.new(repo, source).resolve

      return if old_oid == new_oid

      ff_error = fast_forward_error(old_oid, new_oid)

      if @options[:force] || forced || ff_error.nil?
        @updates[target] = [source, ff_error, old_oid, new_oid]
      else
        @errors.push([[source, target], ff_error])
      end
    end

    private def select_deletion(target)
      if @conn.capable?("delete-refs")
        @updates[target] = [nil, nil, @remote_refs[target], nil]
      else
        @errors.push([[nil, target], "remote does not support deleting refs"])
      end
    end

    private def send_update(ref, old_oid, new_oid)
      old_oid = nil_to_zero(old_oid)
      new_oid = nil_to_zero(new_oid)

      @conn.send_packet("#{old_oid} #{new_oid} #{ref}")
    end

    private def nil_to_zero(oid) = oid.nil? ? ZERO_OID : oid

    private def send_objects
      revs = @updates.values.map(&:last).compact
      return if revs.empty?

      revs += @remote_refs.values.map { "^#{_1}" }

      send_packed_objects(revs)
    end

    private def print_summary
      if @updates.empty? && @errors.empty?
        @stderr.puts "Everything up-to-date"
      else
        @stderr.puts "To #{@push_url}"
        @errors.each { |ref_names, error| report_ref_update(ref_names, error) }
      end
    end

    private def recv_report_status
      return unless @conn.capable?("report-status") && !@updates.empty?

      unpack_result = UNPACK_LINE.match(@conn.recv_packet)[1]

      unless unpack_result == "ok"
        @stderr.puts "error: remote unpack failed: #{unpack_result}"
      end

      @conn.recv_until(nil) { handle_status(_1) }
    end

    private def handle_status(line)
      return unless (match = UPDATE_LINE.match(line))

      status = match[1]
      ref = match[2]
      error = (status == "ok") ? nil : match[3].strip

      @errors.push([ref, error]) if error
      report_update(ref, error)

      targets = Remotes::Refspec.expand(@fetch_specs, [ref])

      targets.each do |local_ref, (remote_ref, _)|
        new_oid = @updates[remote_ref].last
        repo.refs.update_ref(local_ref, new_oid) unless error
      end
    end

    private def report_update(target, error)
      source, ff_error, old_oid, new_oid = @updates[target]
      ref_names = [source, target]
      report_ref_update(ref_names, error, old_oid, new_oid, ff_error.nil?)
    end
  end
end

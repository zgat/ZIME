# Bounded subprocesses for test tools. No Timeout/Open3 reader-thread cleanup:
# this owner drains both pipes, writes input and terminates its own process group.
module TestProcess
  class DeadlineExceeded < StandardError
    attr_reader :stdout, :stderr
    def initialize(command, stdout, stderr)
      @stdout, @stderr = stdout, stderr
      super("test subprocess deadline exceeded: #{command.first}")
    end
  end
  class OutputExceeded < StandardError; end
  class Cancelled < StandardError
    attr_reader :signal
    def initialize(signal)
      @signal = signal
      super("test subprocess cancelled: #{signal}")
    end
  end

  def self.now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.signal_group(signal, pid)
    Process.kill(signal, -pid)
  rescue Errno::ESRCH
    nil
  end

  def self.capture(*command, timeout: 600, stdin_data: "", term_grace: 0.25, output_limit: 32 * 1024 * 1024,
    inherit_stdio: false, cancelled: nil, chdir: nil)
    limits = [timeout, term_grace]
    raise ArgumentError, "invalid subprocess limits" unless limits.all? { |v| (v.is_a?(Integer) || v.is_a?(Float)) && v.finite? } &&
      timeout > 0 && term_grace >= 0 && output_limit.is_a?(Integer) && output_limit > 0
    raise ArgumentError, "stdin must be a String" unless stdin_data.is_a?(String)
    raise ArgumentError, "invalid inherited IO mode" unless [true, false].include?(inherit_stdio) &&
      (!inherit_stdio || stdin_data.empty?)
    raise ArgumentError, "invalid cancellation observer" unless cancelled.nil? || cancelled.respond_to?(:call)
    raise ArgumentError, "invalid working directory" unless chdir.nil? || (chdir.is_a?(String) && !chdir.empty?)
    environment = command.first.is_a?(Hash) ? command.shift : {}
    raise ArgumentError, "empty command" if command.empty?
    # Ruby 2.6 treats a lone command String as shell syntax. Always use the
    # explicit executable/argv0 form, including commands with no arguments.
    spawn_command = command.dup
    spawn_command[0] = [command.first, command.first] unless command.first.is_a?(Array)
    descriptors = []
    spawn_options = {pgroup: true}
    spawn_options[:chdir] = chdir if chdir
    if inherit_stdio
      # The child writes directly to the caller's terminal/files/pipeline.
      # Backpressure blocks the child, never this deadline/cancellation owner.
      pid = Process.spawn(environment, *spawn_command, **spawn_options, in: STDIN, out: STDOUT, err: STDERR)
      buffers = {}
    else
      input_read, input_write = IO.pipe.tap { |pair| descriptors.concat(pair) }
      output_read, output_write = IO.pipe.tap { |pair| descriptors.concat(pair) }
      error_read, error_write = IO.pipe.tap { |pair| descriptors.concat(pair) }
      pid = Process.spawn(environment, *spawn_command, **spawn_options, in: input_read, out: output_write, err: error_write)
      [input_read, output_write, error_write].each(&:close)
      buffers = { output_read => +"".b, error_read => +"".b }
    end
    readers = buffers.keys
    offset = 0
    input_write.close if input_write && stdin_data.empty?
    deadline = now + timeout
    expired = false
    status = nil
    until status && readers.empty?
      requested_signal = cancelled&.call
      raise ArgumentError, "invalid cancellation signal" unless requested_signal.nil? || %w[INT TERM HUP].include?(requested_signal)
      if requested_signal && !expired
        cancellation = requested_signal
        expired = true
        signal_group(requested_signal, pid)
        deadline = now + term_grace
      end
      unless status
        waited = Process.waitpid2(pid, Process::WNOHANG)
        status = waited[1] if waited
      end
      break if status && readers.empty?
      if now >= deadline
        if expired
          signal_group("KILL", pid)
          killed = true
          break
        end
        expired = true
        signal_group("TERM", pid)
        deadline = now + term_grace
      end
      writers = input_write && !input_write.closed? ? [input_write] : []
      ready = IO.select(readers, writers, nil, [deadline - now, 0.02].min.clamp(0, 0.02))
      next unless ready
      ready[0].each do |io|
        chunk = io.read_nonblock(65_536, exception: false)
        if chunk.nil?
          readers.delete(io); io.close
        elsif chunk != :wait_readable
          buffers[io] << chunk
          raise OutputExceeded, "test subprocess output limit exceeded" if buffers.values.sum(&:bytesize) > output_limit
        end
      end
      ready[1].each do |io|
        begin
          written = io.write_nonblock(stdin_data.byteslice(offset, 65_536), exception: false)
          offset += written if written.is_a?(Integer)
          io.close if offset == stdin_data.bytesize
        rescue Errno::EPIPE
          io.close
        end
      end
    end
    # The deadline applies to descendants retaining stdout/stderr, not just the
    # direct child. Always reap that child before returning to fixture cleanup.
    if expired && !killed
      signal_group("KILL", pid)
      killed = true
    end
    status ||= Process.waitpid2(pid)[1]
    stdout, stderr = inherit_stdio ? ["", ""] : buffers.values.map { |s| s.force_encoding(Encoding.default_external) }
    raise Cancelled.new(cancellation) if cancellation
    raise DeadlineExceeded.new(command, stdout, stderr) if expired
    [stdout, stderr, status]
  ensure
    if pid
      signal_group("KILL", pid) unless killed
      begin
        Process.waitpid(pid) unless status
      rescue Errno::ECHILD
        nil
      end
    end
    descriptors&.each { |io| io.close unless io.closed? }
  end
end

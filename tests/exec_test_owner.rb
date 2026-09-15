#!/usr/bin/env ruby
# A background Bash command inherits SIGINT ignored. Reset it before entering
# another shell owner, and create a group containing its foreground commands.
# exec keeps the PID tracked by the parent; no extra waiting process remains.
%w[INT TERM HUP].each { |signal| Signal.trap(signal, "DEFAULT") }
Process.setpgrp
executable = ARGV.shift
abort "usage: exec_test_owner.rb EXECUTABLE [ARGS...]" unless executable
exec([executable, executable], *ARGV)

#!/usr/bin/env python3
"""Run a command on a pty and flush its log so the recorder can see ESP_SIGNAL lines."""
import errno
import os
import pty
import sys
import time

def main():
    if len(sys.argv) < 4:
        sys.exit("usage: ptylog.py LOGFILE MARKFILE command...")
    log = open(sys.argv[1], "w", buffering=1)
    marks_path = sys.argv[2]
    cmd = sys.argv[3:]
    os.environ["NSUnbufferedIO"] = "YES"
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(cmd[0], cmd)
    buf = ""
    while True:
        try:
            data = os.read(fd, 4096)
        except OSError as exc:
            if exc.errno == errno.EIO:
                break
            raise
        if not data:
            break
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
        text = data.decode("utf-8", "replace")
        log.write(text)
        log.flush()
        buf += text
        while "\n" in buf:
            line, buf = buf.split("\n", 1)
            marker = "ESP_SIGNAL "
            idx = line.find(marker)
            if idx == -1:
                continue
            name = line[idx + len(marker):].strip().split()[0]
            with open(marks_path, "a", buffering=1) as marks:
                marks.write(f"{name} {time.time():.3f}\n")
    _, status = os.waitpid(pid, 0)
    code = os.waitstatus_to_exitcode(status)
    sys.exit(code)

if __name__ == "__main__":
    main()

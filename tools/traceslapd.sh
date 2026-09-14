PID=$(pgrep -x slapd)
sudo gdb -p $PID -batch -ex "thread apply all bt" > /tmp/slapd_backtrace.txt 2>&1
cat /tmp/slapd_backtrace.txt

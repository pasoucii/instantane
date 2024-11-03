#        _.---._    /\\
#     ./'       "--`\//			instantane - makefile
#   ./              o \			Oct 9 2024
#  /./\  )______   \__ \
# ./  / /\ \   | \ \  \ \
#    / /  \ \  | |\ \  \7
#     "     "    "  "
objs = inst.o err.o int.o printf.o
exec = inst

inst: $(objs)
	ld	-o $(exec) $(objs)
%.o: %.s
	as	$< -o $@ -g
test_printf:
	as printf.s -o printf.o
	ld -o printf_tester printf.o
clean:
	rm	-rf $(objs) $(exec) printf_tester

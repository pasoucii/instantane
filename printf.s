#        _.---._    /\\
#     ./'       "--`\//			instantane - tiny printf implementation
#   ./              o \			Oct 9 2024
#  /./\  )______   \__ \
# ./  / /\ \   | \ \  \ \
#    / /  \ \  | |\ \  \7
#     "     "    "  "
.section    .rodata
    .nullstr_msg:   .string "[printf:fatal]: null string (rsi)\n"
    .nullstr_len:   .quad   34

    .buffovr_msg:   .string "[printf:fatal]: buffer overflow\n"
    .buffovr_len:   .quad   32

    .expectingfmt_msg:  .string "[printf:fatal]: format expected\n"
    .expectingfmt_len:   .quad   32

    .fmt: .string "hola %d hola %d\n"

    .buffsz: .quad 1024
    .nbufsz: .quad  32

.section    .bss
    .buffer:    .zero   1024
    .numbuf:    .zero   32

.section    .text
.include    "macros.inc"

.globl  _printf_

#  ________________________________________
# / implementation of printf function, rdi \
# | gets the stream to write and rsi the   |
# | formated string. Values must be pushed |
# | into the stack in the inverse order    |
# \ they were defined into the fmt-str     /
#  ----------------------------------------
#         \   ^__^
#          \  (oo)\_______
#             (__)\       )\/\
#                 ||----w |
#                 ||     ||
_printf_:
    cmpq    $0, %rsi
    je      .fatal_null_str
    pushq   %rbp
    movq    %rsp, %rbp
    subq    $16, %rsp
    # -8(%rbp): stream to be written.............
    # -16(%rbp): number of bytes to be written...
    # -24(%rbp): nth argument....................
    movq    %rdi, -8(%rbp)
    movq    $0, -16(%rbp)
    movq    $0, -24(%rbp)
    # r8: reads the fmt string...
    # r9: modifies the buffer....
    movq    %rsi, %r8
    leaq    .buffer(%rip), %r9
._pfloop:
    # Making sure there is not overflow
    movq    -16(%rbp), %rax
    cmpq    %rax, .buffsz(%rip)
    je      .fatal_buff_overflow
    # Making sure there still is content to be read
    movzbl  (%r8), %eax
    testl   %eax, %eax
    jz      ._pffini
    # Check for possible formats
    cmpl    $'%', %eax
    je      ._pfformat
    # If ain't format just write the byte into the buffer
    incq    -16(%rbp)
    movb    %al, (%r9)
    jmp     ._pfcontinue
._pfformat:
    incq    %r8
    movzbl  (%r8), %eax
    cmpl    $'%', %eax
    je      ._pf_fmt_pct
    # r10 will hold this argument
    movq    -24(%rbp), %rbx
    leaq    16(%rbp), %r10
    movq    (%r10, %rbx, 8), %r10
    incq    -24(%rbp)
    cmpl    $'d', %eax
    je      ._pf_fmt_num
    cmpl    $'s', %eax
    je      ._pf_fmt_str
    cmpl    $'c', %eax
    je      ._pf_fmt_chr
    jmp     .fatal_expecting_fmt

#  ____________________
# < format for numbers >
#  --------------------
#   \
#    \
#        __
#       UooU\.'@@@@@@`.
#       \__/(@@@@@@@@@@)
#            (@@@@@@@@)
#            `YY~~~~YY'
#             ||    ||
._pf_fmt_num:
    cmpq    $0, %r10
    jne      ._pf_fmt_num_nz
    movb    $'0', (%r9)
    incq    -16(%rbp)
    jmp     ._pfcontinue
._pf_fmt_num_nz:
    leaq    .numbuf(%rip), %r11
    addq    .nbufsz(%rip), %r11
    decq    %r11
    cmpq    $0, %r10
    jg      ._pf_fmt_num_pos
    movb    $'-', (%r9)
    incq    %r9
    incq    -16(%rbp)
    negq    %r10
._pf_fmt_num_pos:
    testq   %r10, %r10
    jz      ._pf_fmt_num_write
    # Checking there is not number overflow.
    cmpq    %r11, .numbuf(%rip)
    je      .fatal_buff_overflow
    # Checking there is not message overflow.
    movq    -16(%rbp), %rax
    cmpq    %rax, .buffsz(%rip)
    je      .fatal_buff_overflow
    # Getting the last digit of the number and
    # the number / 10 goes to r10 as the new number.
    xorq    %rdx, %rdx
    movq    %r10, %rax
    movq    $10, %rcx
    divq    %rcx
    movq    %rax, %r10
    # Writing this digit into r11
    addq    $'0', %rdx
    movb    %dl, (%r11)
    decq    %r11
    incq    -16(%rbp)
    jmp     ._pf_fmt_num_pos
._pf_fmt_num_write:
    incq    %r11
._pf_fmt_num_write_loop:
    movzbl  (%r11), %eax
    testl   %eax, %eax
    jz      ._pf_fmt_end
    movb    %al, (%r9)
    movb    $0, (%r11)
    incq    %r9
    incq    %r11
    jmp     ._pf_fmt_num_write_loop

#  ____________________
# < format for strings >
#  --------------------
#   \
#    \
#        __
#       UooU\.'@@@@@@`.
#       \__/(@@@@@@@@@@)
#            (@@@@@@@@)
#            `YY~~~~YY'
#             ||    ||
._pf_fmt_str:
    movzbl  (%r10), %ebx
    testl   %ebx, %ebx
    jz      ._pf_fmt_end
    movq    -16(%rbp), %rax
    cmpq    %rax, .buffsz(%rip)
    je      .fatal_buff_overflow
    movb    %bl, (%r9)
    incq    -16(%rbp)
    incq    %r10
    incq    %r9
    jmp     ._pf_fmt_str

#  ____________________
# < format for charcts >
#  --------------------
#   \
#    \
#        __
#       UooU\.'@@@@@@`.
#       \__/(@@@@@@@@@@)
#            (@@@@@@@@)
#            `YY~~~~YY'
#             ||    ||
._pf_fmt_chr:
    movb    %r10b, (%r9)
    incq    -16(%rbp)
    jmp     ._pfcontinue

#  ________________
# < format for %'s >
#  ----------------
#   \
#    \
#        __
#       UooU\.'@@@@@@`.
#       \__/(@@@@@@@@@@)
#            (@@@@@@@@)
#            `YY~~~~YY'
#             ||    ||
._pf_fmt_pct:
    movb    $'%', (%r9)
    incq    -16(%rbp)
    jmp     ._pfcontinue

._pf_fmt_end:
    decq    %r9
._pfcontinue:
    incq    %r8
    incq    %r9
    jmp     ._pfloop
._pffini:
    movq    -16(%rbp), %rdx
    leaq    .buffer(%rip), %rsi
    movq    -8(%rbp), %rdi
    movq    $1, %rax
    syscall
    movq    -16(%rbp), %rax
    leave
    ret

#  _____________
# < Errors here >
#  -------------
#  \
#   \
#    \ >()_
#       (__)__ _
.fatal_null_str:
    __eputs .nullstr_msg(%rip), .nullstr_len(%rip)
    __fini  $1
.fatal_buff_overflow:
    __eputs .buffovr_msg(%rip), .buffovr_len(%rip)
    __fini  $2
.fatal_expecting_fmt:
    __eputs .expectingfmt_msg(%rip), .expectingfmt_len(%rip)
    __fini  $3

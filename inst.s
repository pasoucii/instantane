#        _.---._    /\\
#     ./'       "--`\//			instantane - main file & lexer
#   ./              o \			Oct 9 2024
#  /./\  )______   \__ \
# ./  / /\ \   | \ \  \ \
#    / /  \ \  | |\ \  \7
#     "     "    "  "
.section    .text
.globl  _start

.include    "macros.inc"

_start:
    # Checking number of arguments is correct
    # it must be two.
    popq    %rax
    cmpq    $2, %rax
    jne     fatal_usage
    popq    %rdi
    popq    %rdi
    # Setting up the stack for this function
    #   -8(%rbp): file's content        <ptr>
    #  -16(%rbp): file's length         <quad>
    #  -24(%rbp): number line           <quad>
    #  -32(%rbp): line offset           <quad>
    #  -40(%rbp): current token         <ptr>
    #  -48(%rbp): nth token             <quad>
    #  -56(%rbp): [ ] counter           <quad>
    pushq   %rbp
    movq    %rsp, %rbp
    subq    $64, %rsp
    movq    $1, -24(%rbp)
    movq    $-1, -32(%rbp)
    leaq    Tokens(%rip), %rax
    movq    %rax, -40(%rbp)
    movq    $0, -48(%rbp)
    movq    $0, -56(%rbp)
    # rdi saves the name of the file to be
    # interpreted: edi = open(rdi, O_RDONLY, 0)
    xorq    %rsi, %rsi
    xorq    %rdx, %rdx
    movq    $2, %rax
    syscall
    cmpq    $3, %rax
    jl      fatal_opening_file
    movl    %eax, %edi
    # Getting file's size by lseek syscalls.
    # r15 = lseek(rdi, 0, SEEK_END)
    # (void) lseek(rdi, 0, SEEK_SET)
    xorq    %rsi, %rsi
    movq    $2, %rdx
    movq    $8, %rax
    syscall
    movq    %rax, %r15
    movq    $0, %rdx
    movq    $8, %rax
    syscall
    # Mapping file's content into memory by using mmap syscall.
    # rax = mmap(NULL, r15 -> rsi, PROT_READ | PROT_WRITE, MAP_PRIVATE, edi -> r8, 0)
    movq    %rdi, %r8
    xorq    %rdi, %rdi
    movq    %r15, %rsi
    movq    $1, %rdx
    movq    $2, %r10
    xorq    %r9, %r9
    movq    $9, %rax
    syscall
    cmpq    $-1, %rax
    je      fatal_readfile
    movq    %rax, -8(%rbp)
    movq    %rsi, -16(%rbp)
    # Closing file.
    movq    %r8, %rdi
    movq    $3, %rax
    syscall
    # Lexer begins from here...
    # r15 will be a pointer to the current location
    # in the file.
    movq    -8(%rbp), %r15
    leaq    Loops(%rip), %r8

.lexer_eats:
    # Making sure ain't the EOF
    movzbl  (%r15), %eax
    testl   %eax, %eax
    jz      .lexer_ends
    movl    %eax, %edi
    incq    -32(%rbp)
    call    ._check_chr_
    testl   %eax, %eax
    jz      .lx_skip_ch
    # Cheking `Tokens` array boundaries.
    movq    -48(%rbp), %rax
    cmpq    %rax, tokens_max(%rip)
    je      fatal_toklim
    # Setting context for this token:
    # 1. context as string...
    # 2. number line.........
    # 3. with an offset of...
    movq    -40(%rbp), %r8
    movq    %r15, 0(%r8)
    movq    -24(%rbp), %rax
    movq    %rax, 8(%r8)
    movq    -32(%rbp), %rax
    movq    %rax, 16(%r8)
    # An optimization can be performed when the lexer find
    # tokens and it's to collect them by chunks since it's
    # pretty usual findn more than one token at the time.
    # Therefore the lexer groups them by chunks of a length
    # determinated by '_times_per_token_', this optimization
    # cannot be done with '[' and ']' tokens since they behave
    # in a different way.
    cmpl    $'[', %edi
    je      .lx_handle_opening
    cmpl    $']', %edi
    je      .lx_handle_closing
    # Getting and setting chunk size for current 'accumulative' token.
    leaq    -24(%rbp), %r14
    leaq    -32(%rbp), %r13
    call    ._times_per_token_
    movq    %rax, 24(%r8)
    jmp     .lx_advance_one_token
.lx_handle_opening: 
    # Making sure there still is enough capacity
    # to keep collecting `[` tokens...
    movq    -56(%rbp), %rbx
    cmpq    loops_max(%rip), %rbx 
    je      fatal_pair
    # Setting the mark for this token.
    # The mark is its position among all
    # the other tokens aka an index.
    movq    -48(%rbp), %rcx
    movq    %rcx, 24(%r8)
    # `Loops` is a stack of '[' token addresses.
    # Storing this `[` token.
    leaq    Loops(%rip), %rax
    movq    %r8, 0(%rax, %rbx, 8)
    incq    -56(%rbp)
    jmp     .lx_advance_one_token
.lx_handle_closing:
    # Making sure there is a `[` token to pair
    # `]` token with.
    movq    -56(%rbp), %rbx
    cmpq    $0, %rbx
    je      fatal_pair
    # r9 = Loops[rbx - 1] (r9 is a ptr to the last `[` pushed)
    decq    %rbx
    leaq    Loops(%rip), %rax
    movq    (%rax, %rbx, 8), %r9
    # Setting position where the pair of ']' can be found.
    movq    24(%r9), %rax
    movq    %rax, 24(%r8)
    # Setting position where the pair of '[' can be found.
    movq    -48(%rbp), %rax
    movq    %rax, 24(%r9)
    # One address is gonna be poped
    decq    -56(%rbp)
.lx_advance_one_token:
    incq    -48(%rbp)
    # Getting index of new token.
    movq    -48(%rbp), %rax
    movq    token_size(%rip), %rbx
    mulq    %rbx
    leaq    Tokens(%rip), %rbx
    leaq    (%rbx, %rax), %rax
    movq    %rax, -40(%rbp)
    jmp     .lx_continue
.lx_skip_ch:
    # If the char is a newline the lexer parameters
    # must be updated and then keep eating...
    cmpl    $'\n', %edi
    jne     .lx_continue
    incq    -24(%rbp)
    movq    $-1, -32(%rbp)
.lx_continue:
    incq    %r15
    jmp     .lexer_eats
.lexer_ends:
    movq    -56(%rbp), %rdi
    testq   %rdi, %rdi
    jz      .get_ready_for_interp
    call    _fatal_pairs_
    # unmapping memory used for reading the file.
    movq    $6, %r15
    jmp     .unmmap_and_finish
.get_ready_for_interp:
    movq    -48(%rbp), %rdi
    call    _int_
    movq    $0, %r15
.unmmap_and_finish:
    # unmapping memory used for reading the file.
    movq    -8(%rbp), %rdi
    movq    -16(%rbp), %rsi
    movq    $11, %rax
    syscall
    __fini  %r15

#  _______________________________________
# / checks if whatever stored into edi is \
# \ token                                 /
#  ---------------------------------------
#         \   ^__^
#          \  (oo)\_______
#             (__)\       )\/\
#                 ||----w |
#                 ||     ||
._check_chr_:
    movl    $1, %eax
    cmpl    $'.', %edi
    je      ._cc_fini
    cmpl    $',', %edi
    je      ._cc_fini
    cmpl    $'[', %edi
    je      ._cc_fini
    cmpl    $']', %edi
    je      ._cc_fini
    cmpl    $'<', %edi
    je      ._cc_fini
    cmpl    $'>', %edi
    je      ._cc_fini
    cmpl    $'+', %edi
    je      ._cc_fini
    cmpl    $'-', %edi
    je      ._cc_fini
    movl    $0, %eax
._cc_fini:
    ret

#  _______________________________________
# / Gets the number of times a token      \
# | appears in a row: r14 <ptr> to number |
# \ line, r13 <ptr> to line offset        /
#  ---------------------------------------
#         \   ^__^
#          \  (oo)\_______
#             (__)\       )\/\
#                 ||----w |
#                 ||     ||
._times_per_token_:
    movq    $1, %rcx
    movzbl  (%r15), %ebx
    # getting the next character
    incq    %r15
    incq    (%r13)
._tpt_search:
    movzbl  (%r15), %edi
    cmpl    $0, %edi
    je      ._tpt_fini
    call    ._check_chr_
    testl   %eax, %eax
    jz      ._tpt_non_token
    cmpl    %ebx, %edi
    jne     ._tpt_fini
    incq    %rcx
    jmp     ._tpt_continue
._tpt_non_token:
    cmpl    $'\n', %edi
    jne     ._tpt_continue
    movq    $-1, (%r13)
    incq    (%r14)
._tpt_continue:
    incq    %r15
    incq    (%r13)
    jmp     ._tpt_search
._tpt_fini:
    decq    %r15
    decq    (%r13)
    movq    %rcx, %rax
    ret

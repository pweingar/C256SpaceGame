;;
;; Macros
;;

setaxs      .macro
            SEP #$30
            .as
            .xs
            .endm

setas       .macro
            SEP #$20
            .as
            .endm

setxs       .macro
            SEP #$10
            .xs
            .endm

setaxl      .macro
            REP #$30
            .al
            .xl
            .endm

setal       .macro
            REP #$20
            .al
            .endm

setxl       .macro
            REP #$10
            .xl
            .endm

setdp       .macro
            PHP
            setal
            PHA
            LDA #\1
            TCD
            PLA
            PLP
            .dpage \1
            .endm

setdbr      .macro
            PHP
            setas
            PHA
            LDA #\1
            PHA
            PLB
            PLA
            PLP
            .databank \1
            .endm

; Compile a word definition
DEFWORD     .macro name, flags, previous
            .byte MAXWORDLEN <? len(\name)      ; The length of the word (max 16)
            .text format("%-16s",\name)         ; The word to define
            .byte \flags                        ; The flags for the word
            .word <>\previous                   ; The pointer to the previous word in the vocabulary
            .endm 

;;;
;;; Interrupt Handler
;;;

INITIRQ         .proc
                PHP

                setal
                LDA HIRQ                    ; Save the old interrupt handler
                STA OLDIRQ

                LDA #<>HANDLEIRQ            ; Take control of the IRQ vector
                STA HIRQ

                setas
                LDA #$4C                    ; JMP opcode
                STA JMPOPCODE               ; Save it for jumps

                LDA @lINT_MASK_REG0         ; Enable SOF interrupts
                AND #~FNX0_INT00_SOF
                STA @lINT_MASK_REG0

                PLP
                RTS
                .pend

;
; Handle IRQs
;
HANDLEIRQ       .proc
                setaxl
                PHB
                PHD
                PHA
                PHX
                PHY
                PHP

                setas 					; Set 8bits
                ; Go Service the Start of Frame Interrupt Interrupt
                ; IRQ0
                ; Start of Frame Interrupt
                LDA @lINT_PENDING_REG0
                CMP #$00
                BEQ done

                LDA @lINT_PENDING_REG0
                AND #FNX0_INT00_SOF
                CMP #FNX0_INT00_SOF
                BNE done
                STA @lINT_PENDING_REG0

                ; Start of Frame Interrupt
                JSR UPDATE              ; Update all the active sprites that require an update
                JSR EXECTONE            ; Execute any pending tone instruction

                setas
                LDA #ML_STAT_ANIMATE    ; Flag that we can update any active sprites
                STA STATUS

done            PLP
                PLY
                PLX
                PLA
                PLD
                PLB

                ; RTI
                JMP JMPOPCODE           ; Go back to the original handler
                .pend

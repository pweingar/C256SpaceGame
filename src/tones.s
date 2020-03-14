;;
;; A tone / music playing engine for the SN76489
;;
;; Instructions:
;; SET_VOLUME channel, attenuation
;; SET_FREQUENCY channel, frequency
;; WAIT ticks
;; FINISH
;;
;; 00000000 xxxxxxxx xxxxxxxx -- Finish
;; xxCC0001 xxxxAAAA xxxxxxxx -- Set attenuation
;; xxCC0010 FFFFFFFF xxxxxxFF -- Set frequency
;; xxxx0011 DDDDDDDD DDDDDDDD -- Wait D ticks
;; xxCC0100 SSSSRRRR AAAADDDD -- Set ADSR envelope
;; xxCC0101 xxxxxxxx xxxxxxxx -- Release
;;
;; The engine can drive a voice directly using the TONE_SET_ATTEN and TONE_SET_FREQ commands
;; Or it can use the ADSR envelope generator. The engine starts the ATTACK phase with TONE_START_ENV
;; While the envelope is in the SUSTAIN phase, the engine moves it to the RELEASE phase with TONE_RELEASE.
;;
;; ATTACK = attenuation steps to change per tick (goes from 15 [off] to 0 [full])
;; DECAY = attenuation steps to change per tick (goes from 0 [full] to SUSTAIN)
;; SUSTAIN = the attenuation level to hold until the engine releases the note
;; RELEASE = attenuation steps to change per tick (goes from SUSTAIN to 15 [off])
;;
;;              DECAY
;; 00          /\
;;            /  \
;;           /    \
;;          /      \__________________        <=== SUSTAIN
;;         /                          \      
;;        /                            \
;; 0F ___/                              \___
;;       ATTACK                     RELEASE              
;;

;;
;; Macros
;;

TONE_OP     .macro opcode, argument
            .byte \opcode
            .word \argument
            .endm

TONE_FREQ   .macro freq
            .byte TONE_SET_FREQ
            .word 3575800 / (32 * \freq)
            .endm

;;
;; Defines
;;

TONE_FINISH = $00           ; End the tones
TONE_SET_ATTEN = $01        ; Set attenuation for the channel
TONE_SET_FREQ = $02         ; Set the frequency of the channel
TONE_WAIT = $03             ; Wait a number of ticks
TONE_SET_ENV = $04          ; Set the ADSR envelope
TONE_START_ENV = $05        ; Start the envelope cycle (ADS...)
TONE_RELEASE = $06          ; Release the note (...R)

TONE_STATE_SNC = $00        ; Channel is silent
TONE_STATE_ATK = $01        ; Envelope is in the Attack stage
TONE_STATE_DCY = $02        ; Envelope is in the Decay stage
TONE_STATE_SUS = $03        ; Envelope is in the Sustain stage
TONE_STATE_REL = $04        ; Envelope is in the Release stage

;;
;; Structures
;;

; A structure to track the envelope of a sound
ENVELOPE        .struct
CHANNEL         .byte ?     ; Channel code appropriate for sending commands 00000000, 00100000, 01000000
STATE           .byte ?     ; The current state of the envelope: silent, attack, decay, sustain, release
ATTACK          .byte ?     ; The attack rate (attenuation values per tick)
DECAY           .byte ?     ; The decay rate (attenuation values per tick)
SUSTAIN         .byte ?     ; The sustain level (attenuation value)
RELEASE         .byte ?     ; The release rate (attenuation values per tick)
ATTENUATION     .byte ?     ; The current attenuation value
                .ends

;;
;; Variables
;;

.section variables
TONECOUNT       .word ?                 ; Delay counter for executing instructions (if negative, to not execute tone instructions)
TONEPTR         .dword ?                ; Pointer to tone instruction to execute
CH0_ENV         .dstruct ENVELOPE       ; The envelope for channel 0
.send

;;
;; Code
;;

;
; Initialize the tone generator
;
INITTONE        .proc
                PHP

                setal
                LDA #$FFFF              ; By default we play nothing
                STA TONECOUNT

                STZ TONEPTR             ; Point to nothing
                STZ TONEPTR+2

                setas
                LDA #$80                ; Shut off voice 0
                STA @l SN76489
                LDA #$00
                STA @l SN76489

                LDA #$9F
                STA @l SN76489

                LDA #$A0                ; Shut off voice 1
                STA @l SN76489
                LDA #$00
                STA @l SN76489

                LDA #$BF
                STA @l SN76489

                LDA #$C0                ; Shut off voice 2
                STA @l SN76489
                LDA #$00
                STA @l SN76489

                LDA #$DF
                STA @l SN76489
       
                STZ CH0_ENV.CHANNEL     ; Set the channel code for the envelope
                STZ CH0_ENV.STATE       ; Set the state to silence

                LDA #$04                ; Initialize the envelope to something ordinary
                STA CH0_ENV.ATTACK
                STA CH0_ENV.DECAY

                LDA #$01
                STA CH0_ENV.RELEASE
                LDA #$05
                STA CH0_ENV.SUSTAIN

                PLP
                RTS
                .pend

;
; Execute a tone instruction
;
EXECTONE        .proc
                PHA
                PHX
                PHY
                PHP

                setxl
                LDX #<>CH0_ENV          ; Process the envelope on channel 0
                JSR PROCESSENV

                setal
                LDA TONECOUNT           ; Check the tone counter
                BEQ get_opcode          ; If it's 0, get the opcode
                BPL tick_down           ; If it's positive, we need to decrement            
                BRL done                ; If it's negative, we shouldn't do anything

tick_down       DEC TONECOUNT           ; Decrement the wait counter
                BNE done                ; If it's not zero, keep waiting

advance         setal
                CLC                     ; Advance the TONEPTR to the next instruction
                LDA TONEPTR
                ADC #3
                STA TONEPTR
                LDA TONEPTR+2
                ADC #0
                STA TONEPTR+2

done            PLP
                PLY
                PLX
                PLA
                RTS

get_opcode      setas
                LDY #0
                LDA [TONEPTR],Y         ; Get the opcode
                AND #$0F                ; Filter to just the opcode bits

                BEQ do_finish           ; If it's 0, we're done playing the sounds

                CMP #TONE_SET_ATTEN     ; Is it SET_ATTENUATE
                BEQ do_atten

                CMP #TONE_SET_FREQ      ; Is it SET_FREQ
                BEQ do_freq

                CMP #TONE_WAIT          ; Is it WAIT?
                BEQ do_wait

                CMP #TONE_SET_ENV       ; Is it SET ENVELOPE?
                BEQ do_set_adsr

                CMP #TONE_START_ENV     ; Start processing an envelope
                BNE chk_release
                BRL do_start

chk_release     CMP #TONE_RELEASE       ; Is it RELEASE?
                BNE advance             ; Otherwise, just skip
                BRL do_release              

                ; Execute a WAIT instruction

do_wait         setal
                LDY #1                  ; We need to set the TONECOUNT
                LDA [TONEPTR],Y
                STA TONECOUNT
                BRA done                ; And return to caller

                ; Set the attenuation on the channel

do_atten        setas
                LDA [TONEPTR],Y         ; Get the opcode
                AND #%00110000          ; Filter out the channel number
                ASL A                   ; Move it to the right spot
                ORA #%10010000          ; Turn it into a set attenuation instruction for the chip
                STA TEMP                ; Save it for the moment

                LDY #1                  ; Get the attenuation
                LDA [TONEPTR],Y
                AND #$0F                ; Filter out any junk
                ORA TEMP                ; Complete the instruction
                STA @l SN76489          ; Send it to the sound chip
                BRA advance             ; And go to the next instruction

                ; Set the frequency on the channel

do_freq         setas
                LDA [TONEPTR],Y         ; Get the opcode
                AND #%00110000          ; Filter out the channel number
                ASL A                   ; Move it to the right spot
                ORA #%10000000          ; Turn it into a set frequency instruction for the chip
                STA TEMP                ; Save it for the moment

                LDY #1                  ; Get the lower four bits of the frequency
                LDA [TONEPTR],Y
                AND #$0F                ; Filter out the higher bits
                ORA TEMP                ; Complete the first byte of the instruction
                STA @l SN76489          ; Send it to the sound chip

                setal
                LDA [TONEPTR],Y         ; Get all the bits of the frequency
                LSR A                   ; Drop the lower 4 bits
                LSR A
                LSR A
                LSR A
                setas
                AND #$3F                ; Filter it to 6 bits
                STA @l SN76489          ; Send it to the sound chip     
                BRL advance             ; And go to the next instruction

                ; Finish executing instructions

do_finish       setal
                LDA #$FFFF              ; Set the counter to -1
                STA TONECOUNT
                BRL done

                ; Set the ADSR envelope for a channel
                ; TODO: generalize to handle all three channels

do_set_adsr     setas
                LDY #1
                LDA [TONEPTR],Y         ; Get the sustain and release values
                AND #$0F
                STA CH0_ENV.RELEASE     ; Set release
                LDA [TONEPTR],Y         ; Get the sustain and release values
                LSR A
                LSR A
                LSR A
                LSR A
                STA CH0_ENV.SUSTAIN     ; Set sustain

                LDY #2
                LDA [TONEPTR],Y         ; Get the attack and decay values
                AND #$0F
                STA CH0_ENV.DECAY       ; Set decay
                LDA [TONEPTR],Y         ; Get the attack and decay values
                LSR A
                LSR A
                LSR A
                LSR A
                STA CH0_ENV.ATTACK      ; Set attack
                BRL advance

                ; Start playing a note using the ADSR envelope

do_start        setas
                LDA #$0F                ; Set the initial attenuation
                STA CH0_ENV.ATTENUATION 

                LDA #TONE_STATE_ATK     ; Move the envelope into the ATTACK state
                STA CH0_ENV.STATE
                BRL advance

                ; Release a note that should be in SUSTAIN mode

do_release      setas
                LDA #TONE_STATE_REL     ; Move the envelope into the RELEASE state
                STA CH0_ENV.STATE
                BRL advance
                .pend

;
; Process the envelope for a channel
;
; Inputs:
;   X = pointer to the channel's structure (must be in bank 0)
;
PROCESSENV      .proc
                PHP
                PHB
                setdbr 0
                setas

                LDA ENVELOPE.STATE,X    ; Check the envelope's state
                BEQ done                ; If it's zero, we don't need to process it
                CMP #TONE_STATE_SUS     ; Is it SUSTAIN?
                BEQ done                ; Yes: we don't do anything here either

                CMP #TONE_STATE_ATK     ; Dispatch: ATTACK?
                BEQ do_attack
                CMP #TONE_STATE_DCY     ; Dispatch: DECAY?
                BEQ do_decay
                CMP #TONE_STATE_REL     ; Dispatch: RELEASE?
                BEQ do_release
              
done            PLB
                PLP
                RTS

                ; Decrease attenuation to 0 by ATTACK rate
do_attack       SEC
                LDA ENVELOPE.ATTENUATION,X  ; Get the attenuation
                SBC ENVELOPE.ATTACK,X       ; Compute the new attenuation
                BPL set_attenuation         ; Is it >= 0? Set the attenuation

                LDA #TONE_STATE_DCY         ; Move the state to DECAY
                STA ENVELOPE.STATE,X
                LDA #$00                    ; And set the attenuation to 0
                BRA set_attenuation

                ; Increase attenuation by DECAY until we reach the SUSTAIN value
do_decay        CLC
                LDA ENVELOPE.ATTENUATION,X  ; Get the attenuation
                ADC ENVELOPE.DECAY,X        ; Compute the new attenuation
                CMP ENVELOPE.SUSTAIN,X      ; Is it at SUSTAIN?
                BLT set_attenuation         ; No: set the attenuation

                LDA #TONE_STATE_SUS         ; Move the state to SUSTAIN until the engine releases the note
                STA ENVELOPE.STATE,X
                LDA ENVELOPE.SUSTAIN,X      ; And set the attenuation to SUSTAIN
                BRA set_attenuation

                ; Increate the attenuation by RELEASE until we reach 15
do_release      CLC
                LDA ENVELOPE.ATTENUATION,X  ; Get the attenuation
                ADC ENVELOPE.RELEASE,X      ; Compute the new attenuation
                CMP #$0F                    ; Is it >15?
                BLT set_attenuation         ; No: set the attenuation

                LDA #TONE_STATE_SNC         ; Move the state to SILENCE
                STA ENVELOPE.STATE,X
                LDA #$0F                    ; And set the attenuation to 15

set_attenuation STA ENVELOPE.ATTENUATION,X  ; Save the new attenuation
                AND #$0F                    ; Make sure we don't have anything extra
                ORA ENVELOPE.CHANNEL,X      ; Add the channel selector bits
                ORA #%10010000              ; Make it an attenuation command
                STA @l SN76489              ; Send the command
                BRL done
                .pend

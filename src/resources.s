;;;
;;; Code to manage resources (mainly RLE graphics data included in the source code)
;;;

;
; Load graphics resources into video memory
;
LOADRSRC        .proc
                PHP
                setaxl

                ; Load the ship sprite stationary data

                LDA #<>SHIP_STATIONARY  ; Set source address to RLE data of the ship pointing up
                STA SRCPTR
                LDA #`SHIP_STATIONARY
                STA SRCPTR+2

                LDA #<>VSHIP_STILL      ; Set the destination address to the location in VRAM where the sprite should be
                STA DSTPTR
                LDA #`VSHIP_STILL
                STA DSTPTR+2

                JSR EXPANDRLE           ; And expand the RLE data into VRAM

                ; Load the ship sprite moving data

                LDA #<>SHIP_UP          ; Set source address to RLE data of the ship pointing up
                STA SRCPTR
                LDA #`SHIP_UP
                STA SRCPTR+2

                LDA #<>VSHIP_UP         ; Set the destination address to the location in VRAM where the sprite should be
                STA DSTPTR
                LDA #`VSHIP_UP
                STA DSTPTR+2

                JSR EXPANDRLE           ; And expand the RLE data into VRAM

                ; Load the torpedo data

                LDA #<>TORPEDO_START    ; Set source address to RLE data of the torpedo
                STA SRCPTR
                LDA #`TORPEDO_START
                STA SRCPTR+2

                LDA #<>VTORPEDO         ; Set the destination address to the location in VRAM where the sprite should be
                STA DSTPTR
                LDA #`VTORPEDO
                STA DSTPTR+2

                JSR EXPANDRLE           ; And expand the RLE data into VRAM

                ; Load the purple flier data

                LDA #<>PURPLE_START     ; Set source address to RLE data of the purple flier
                STA SRCPTR
                LDA #`PURPLE_START
                STA SRCPTR+2

                LDA #<>VPURPLE          ; Set the destination address to the location in VRAM where the sprite should be
                STA DSTPTR
                LDA #`VPURPLE
                STA DSTPTR+2

                JSR EXPANDRLE           ; And expand the RLE data into VRAM

                ; Load the star field tiles

                LDA #<>STARS_START      ; Set source address to RLE data of the star field
                STA SRCPTR
                LDA #`STARS_START
                STA SRCPTR+2

                LDA #<>VSTARS           ; Set the destination address to the location in VRAM where the star field should be
                STA DSTPTR
                LDA #`VSTARS
                STA DSTPTR+2

                JSR EXPANDRLE           ; And expand the RLE data into VRAM

                ; Set up the color look up table

                LDX #<>LUT_START        ; Copy the color pallette to Vicky
                LDY #<>GRPH_LUT1_PTR
                LDA #256 * 4
                MVN `LUT_START,`GRPH_LUT1_PTR

                PLP
                RTS
                .pend

;
; Expand a run-length-encoded image into memory
;
EXPANDRLE       .proc
                PHP
                setas
                STZ COUNT           ; Make sure COUNT is in a known good state
                STZ COUNT+1

pair_loop       LDY #0
                LDA [SRCPTR],Y      ; Get the count of bytes to transfer
                BEQ done            ; If it's zero, we're done
                STA COUNT           ; And save it to the count variable

                INY
                LDA [SRCPTR],Y      ; Get the byte to copy over
                LDY #0

write_loop      STA [DSTPTR],Y      ; And write it to the destination
                INY
                CPY COUNT           ; Have we reached the end?
                BNE write_loop      ; No: keep writing it

                setal
                CLC                 ; Advance the destination pointer
                LDA DSTPTR
                ADC COUNT
                STA DSTPTR
                LDA DSTPTR+2
                ADC #0
                STA DSTPTR+2

                CLC                 ; Advance the srouce pointer to the next pair
                LDA SRCPTR
                ADC #2
                STA SRCPTR
                LDA SRCPTR+2
                ADC #0
                STA SRCPTR+2
                setas

                BRA pair_loop       ; And check it

done            PLP
                RTS
                .pend

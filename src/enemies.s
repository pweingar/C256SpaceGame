;;;
;;; Logic for the enemy game units
;;;

;
; Spawn a purple flier
;
SPAWNPURPLE     .proc
                PHP

                setdbr 0
                setdp SRCPTR

                setaxl
                JSR FINDSPRITE              ; Find an open sprite slot
                BCC done                    ; If we didn't find a slot, just return

                LDA #<>VPURPLE              ; Set the address to the pixmap data
                STA SPRITE.BASEADDR,X
                LDA #`VPURPLE
                STA SPRITE.BASEADDR+2,X

                LDA #6                      ; Set the frame delay count
                STA SPRITE.DELAYDEFAULT,X

                LDA #1                      ; Set the movement delay count
                STA SPRITE.MOVEDELDEF,X

                STZ SPRITE.DX,X             ; Stationary
                STZ SPRITE.DY,X

                LDA #320 - 16               ; Put the sprite in the top-middle of the screen
                STA SPRITE.X,X
                LDA #10
                STA SPRITE.Y,X

                LDA #2
                STA SPRITE.FRAMECOUNT,X
                LDA #1
                STA SPRITE.FRAME,X          ; Initial frame
                LDA SPRITE.DELAYDEFAULT,X
                STA SPRITE.FRAMEDELAY,X     ; Set the frame delay counter

                LDA SPRITE.MOVEDELDEF,X     ; Set the movement delay counter
                STA SPRITE.MOVEDELAY,X

                LDA #$FFFF
                STA SPRITE.WASMOVING,X      ; Set sprite was moving flag to sentinel value

                ; TODO: add animation
                STZ SPRITE.ANIMPROC,X

                setas
                LDA #SP_STAT_ACTIVE | SP_STAT_UPDATE
                STA SPRITE.STATUS,X         ; Flag the sprite as active and ready for an update

done            PLP
                RTS
                .pend
;;;
;;; Code to manage the player and torpedo sprites
;;;

;
; Check joystick
;
CHECKJOY        .proc
                PHP

                SEI

                setal
                STZ SHIP.DX
                STZ SHIP.DY

                setas
                LDA @l JOYSTICK0    ; Get the first joystick
                setal
                AND #$00FF
                STA JOY0

                BIT #%00010000      ; Has the button been pushed?
                BNE check_move      ; No: check the movement buttons

                JSR FIRE            ; Yes: fire the torpedo

check_move      BIT #%00001000
                BEQ right
                BIT #%00000100
                BNE check_ud

left            setal               ; Set the x-coordinate delta to negative
                LDA SHIPSPEED
                EOR #$FFFF
                INC A
                STA SHIP.DX
                BRA check_ud

right           setal               ; Set the x-coordinate delta to positive
                LDA SHIPSPEED
                STA SHIP.DX

check_ud        LDA JOY0
                BIT #%00000010
                BEQ down
                BIT #%00000001
                BNE set_move

up              setal               ; Set the y-coordinate delta to negative
                LDA SHIPSPEED
                EOR #$FFFF
                INC A
                STA SHIP.DY
                BRA set_move

down            setal               ; Set the y-coordinate delta to positive
                LDA SHIPSPEED
                STA SHIP.DY

set_move        JSR SHIPMOVE        ; Set whether or not the ship is moving

done            PLP
                RTS
                .pend

;
; Initialize the player sprite
;
INITPLAYER      .proc
                PHP

                setal
                LDA #6                      ; Set the frame delay count
                STA SHIP.DELAYDEFAULT

                LDA #1                      ; Set the movement delay count
                STA SHIP.MOVEDELDEF

                LDA #2                      ; Set the default speed of the ship
                STA SHIPSPEED

                LDA #320 - 16               ; Put the sprite in the middle of the screen
                STA SHIP.X
                LDA #240 - 16
                STA SHIP.Y

                STZ SHIP.DX                 ; Stationary
                STZ SHIP.DY

                JSR SHIPMOVE                ; Set the sound and graphics for a non-moving ship

                STZ SHIP.FRAME              ; Initial frame
                LDA #1
                STA SHIP.FRAMECOUNT         ; 0 frames in the animation
                LDA SHIP.DELAYDEFAULT
                STA SHIP.FRAMEDELAY         ; Set the frame delay counter

                LDA SHIP.MOVEDELDEF         ; Set the movement delay counter
                STA SHIP.MOVEDELAY

                LDA #$FFFF
                STA SHIP.WASMOVING          ; Set ship was moving flag to sentinel value

                LDA #<>ANIMPLAYER           ; Set the animation procedure for the sprite
                STA SHIP.ANIMPROC

                setas
                LDA #SP_STAT_ACTIVE | SP_STAT_UPDATE
                STA SHIP.STATUS             ; Flag the ship as active and ready for an update

                PLP
                RTS
                .pend

;
; Update the animation frames for the player sprite and the location based on DX and DY
;
ANIMPLAYER      .proc
                PHP

                setdbr 0
                setdp SRCPTR

                LDA SHIP.X
                BPL check_right             ; X >= 0?
                STZ SHIP.X                  ; No: Lock it to 0
                BRA check_top
check_right     CMP BOUNDARY_R              ; X >= the right most position?
                BLT check_top               ; No: we're good
                LDA BOUNDARY_R              ; Yes: lock it to the right most position
                STA SHIP.X

check_top       LDA SHIP.Y
                BPL check_bottom            ; Y >= 0?
                STZ SHIP.Y                  ; No: Lock it to 0
                BRA check_top
check_bottom    CMP BOUNDARY_B              ; X >= the right most position?
                BLT done                    ; No: we're good
                LDA BOUNDARY_B              ; Yes: lock it to the right most position
                STA SHIP.Y

done            PLP
                RTS
                .pend

;
; Set if player is moving
;
; Update sounds and frame animations based on if the player is moving.
;
; Inputs:
;   SHIP.DX, SHIP.DY = indicate movement in X or Y direction
;
SHIPMOVE        .proc
                PHP

                SEI

                setal
                LDA SHIP.DX         ; If DX <> 0 or DY <> 0, the ship is moving
                BNE is_moving
                LDA SHIP.DY
                BNE is_moving

                ; Ship is not moving

                LDA SHIP.WASMOVING  ; Don't do anything if the ship was already stationary
                BEQ done

                LDA #$FF            ; Turn off the engine noise
                JSR NOISE

                LDA #<>VSHIP_STILL  ; Sprite should be of a stationary ship
                STA SHIP.BASEADDR
                SEC
                LDA #`VSHIP_STILL
                SBC #$B0
                STA SHIP.BASEADDR+2

                LDA #1              ; There is only the one frame
                STA SHIP.FRAMECOUNT
                STZ SHIP.FRAME

                STZ SHIP.WASMOVING  ; Set that the ship is no longer moving

                BRA done

is_moving       LDA SHIP.WASMOVING  ; Don't update if ship was already moving
                CMP #1
                BEQ done

                LDA #7              ; Turn on the engine noise
                JSR NOISE

                LDA #<>VSHIP_UP     ; Sprite should be of a flying ship
                STA SHIP.BASEADDR
                SEC
                LDA #`VSHIP_UP
                SBC #$B0
                STA SHIP.BASEADDR+2

                LDA #5              ; There are five frames in this animation
                STA SHIP.FRAMECOUNT
                STZ SHIP.FRAME

                LDA #1              ; Set that the ship is now moving
                STA SHIP.WASMOVING

done            PLP
                RTS
                .pend

;;
;; Torpedo
;;

;
; Initialize the torpedo sprite
;
INITTORPEDO     .proc
                PHP

                setal
                LDA #6                      ; Set the frame delay count
                STA TORPEDO.DELAYDEFAULT

                LDA #1                      ; Set the movement delay count
                STA TORPEDO.MOVEDELDEF

                LDA #320 - 16               ; Put the sprite in the middle of the screen
                STA TORPEDO.X               ; This should be set on FIRE
                LDA #240 - 16
                STA TORPEDO.Y

                STZ TORPEDO.DX              ; Stationary
                LDA #$FFFC                  ; -4 in the Y direction
                STA TORPEDO.DY

                LDA #$FFFF                  ; Set initial frame to -1 to keep it inactive until FIRE
                STA TORPEDO.FRAME
                LDA #8
                STA TORPEDO.FRAMECOUNT      ; 0 frames in the animation
                LDA TORPEDO.DELAYDEFAULT
                STA TORPEDO.FRAMEDELAY      ; Set the frame delay counter

                LDA #<>VTORPEDO             ; Sprite should be of a torpedo
                STA TORPEDO.BASEADDR
                SEC
                LDA #`VTORPEDO
                SBC #$B0
                STA TORPEDO.BASEADDR+2

                LDA TORPEDO.MOVEDELDEF      ; Set the movement delay counter
                STA TORPEDO.MOVEDELAY

                LDA #<>ANIMTORPEDO           ; Set the animation procedure for the sprite
                STA TORPEDO.ANIMPROC

                PLP
                RTS
                .pend

;
; Animate the torpedo
;
ANIMTORPEDO     .proc
                PHP

                LDA TORPEDO.Y               ; Check the height
                BMI cancel                  ; If above the first line, cancel it
                BNE done                    ; If not at the top, we're done

cancel          LDA #$FFFF                  ; If at top, stop processing the torpedo
                STA TORPEDO.FRAME

                setas                       ; And turn off the hardware sprite
                LDA #0
                STA @l SP01_CONTROL_REG

                LDA #0
                STA TORPEDO.STATUS          ; Deactivate the torpedo sprite

done            PLP
                RTS
                .pend

;
; Fire a torpedo
;
FIRE            .proc
                PHA
                PHP

                setal
                LDA TORPEDO.FRAME           ; Is the torpedo already on the screen?
                BPL done                    ; Yes: we don't fire again

                LDA SHIP.X                  ; Set the torpedo position to be the same as the ship
                STA TORPEDO.X
                LDA SHIP.Y
                STA TORPEDO.Y

                LDA #0                      ; Set the starting frame
                STA TORPEDO.FRAME

                setas                       ; Display the torpedo

                LDA #SP_STAT_ACTIVE | SP_STAT_UPDATE
                STA TORPEDO.STATUS          ; Make the torpedo sprite active and ready for update

                LDA #$01
                STA @l SP01_CONTROL_REG

                setal
                LDA #<>TONE_PEW             ; Queue playing the PEW sound
                STA TONEPTR
                LDA #`TONE_PEW
                STA TONEPTR+2
                STZ TONECOUNT

done            PLP
                PLA
                RTS
                .pend

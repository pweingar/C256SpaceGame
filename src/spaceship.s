
                .cpu "65816"

                .include "macros.s"
                .include "vicky_def.s"
                .include "interrupt_def.s"
                .include "joystick_def.s"
                .include "memorymap.s"
                .include "gabe_def.s"
                .include "rtc_def.s"

*=$00FFFC
VRESET          .word START         ; Set the RESET vector to point to the start of the code

;;
;; Data structures
;;

SPRITE          .struct
X               .word ?             ; The x-coordinate of the sprite
Y               .word ?             ; The y-coordinate of the sprite
DX              .word ?             ; The per-tick change to the x-coordinate
DY              .word ?             ; The per-tick change to the y-coordinate
WASMOVING       .word ?             ; Indicates if the sprite was moving on the previous loop
SPRITEADDR      .word ?             ; Address of the sprite's registers in Vicky
BASEADDR        .dword ?            ; The base address (in Vicky space) of the sprite's animation frames (relative to $B0:0000)
FRAME           .word ?             ; The index of the frame to display
FRAMECOUNT      .word ?             ; The number of frames in the sprite animation
FRAMEDELAY      .word ?             ; A counter to time frame flipping
DELAYDEFAULT    .word ?             ; The reset value for the frame delay counter
MOVEDELAY       .word ?             ; A counter to time movement in X,Y
MOVEDELDEF      .word ?             ; The reset value for the movement delay counter
ANIMPROC        .word ?             ; Pointer to the animation procedure for this type of sprite
STATUS          .byte ?             ; Flags to indicate if an UPDATE or ANIMATE call is needed
                                    ;   $80 = Sprite is ACTIVE
                                    ;   $60 = UPDATE needed
                .ends

;;
;; Definitions
;;

; Sprite status flags

SP_STAT_ACTIVE = $80                ; The sprite is active and can be animated and updated
SP_STAT_UPDATE = $60                ; The sprite has changed and needs to be updated to Vicky

; General status

ML_STAT_ANIMATE = $80               ; Flag to indicate that the main loop can ANIMATE all the sprites

; Important memory locations

SN76489 = $AFF100                   ; SN76489 chip's port
HIRQ = $00FFEE                      ; IRQ hardware vector

VSHIP_STILL = $B00000               ; Address in VRAM of sprite image for the stationary space ship
VSHIP_UP = VSHIP_STILL + 32*32      ; Address in VRAM of the sprite image data for the ship pointing up
VTORPEDO = VSHIP_UP + 5*32*32       ; Address in VRAM of the torpedo sprite image data
VSTARS = VTORPEDO + 8*32*32         ; Address of the star field tiles in VRAM

SP_OFF_ADDR = 1                     ; Offset to the address register for a sprite
SP_OFF_X = 4                        ; Offset to the x coordinate register for a sprite
SP_OFF_Y = 6                        ; Offset to the y coordinate register for a sprite

;;
;; Global Variables
;;

.section variables
SRCPTR          .dword ?            ; Pointer to the source for data transfers
DSTPTR          .dword ?            ; Pointer to the destination for data transfers
COUNT           .word ?             ; The number of bytes to copy
TEMP            .dword ?            ; A temporary variable
SHIPSPEED       .word ?             ; Speed of the ship (pixels per vertical blank interrupt)
JMPOPCODE       .byte ?             ; JMP opcode
OLDIRQ          .word ?             ; Old IRQ handler
INDPROC         .word ?             ; Pointer to a procedure to call indirectly
JOY0            .word ?             ; Joystick 0 data
BOUNDARY_R      .word ?             ; Right-most position of a sprite
BOUNDARY_B      .word ?             ; Bottom-most position of a sprite
NOISEVOL        .byte ?             ; Noise attenuation level
TMPPTR          .dword ?            ; A temporary pointer
REGPTR          .dword ?            ; A pointer to Vicky sprite registers
STATUS          .byte ?             ; A status word for controlling the main loop

START_OF_SPRITES = *
SHIP            .dstruct SPRITE     ; The sprite variables for the ship
TORPEDO         .dstruct SPRITE     ; The sprite variables for the torpedo
END_OF_SPRITES  = *
.send

;;
;; Main Code
;;

.section code
START           CLC                 ; Start up in native mode
                XCE

                setdbr 0
                setdp SRCPTR

                setas
                LDA #$FF            ; Set the noise volume to -1 as a sentinel value
                STA NOISEVOL

                setaxl

                SEI                 ; Turn off interrupts
                JSR INITRNG         ; Initialize the random number generator
                JSR LOADRSRC        ; Load the resources into video memory
                JSR INITGRAPH       ; Set up the graphics
                JSR INITTONE        ; Initialize the tone player engine
                JSR INITSTARS       ; Initialize the star field
                JSR INITPLAYER      ; Initialize the player sprite
                JSR INITTORPEDO     ; Initialize the torpedo sprite
                JSR UPDATE
                JSR INITIRQ         ; Set up interrupts
                CLI                 ; Turn interrupts back on

main_loop       setal
                WAI                     ; Wait for interrupt
                JSR CHECKJOY            ; Check for inputs

                setas
                LDA #ML_STAT_ANIMATE    ; Check to see if we can animate the sprites
                TRB STATUS
                BEQ main_loop           ; No: go back to waiting

                JSR ANIMATE             ; Animate all the active sprites
                BRA main_loop

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

;
; Make a noise of a given volume
;
; Inputs:
;   A = attenuation (0 = full volumn, F = off)
;
NOISE           .proc
                PHP

                setas
                AND #$0F            ; Check the attenuation
                CMP NOISEVOL        ; Is it already set?
                BEQ done            ; Yes: don't change anything

                STA NOISEVOL        ; Otherwise, record this volume level

                ORA #$F0            ; Make A an attenuation value for the noise channel
                STA @l SN76489

                LDA #%11100110      ; Make the noise
                STA @l SN76489

done            PLP
                RTS
                .pend

;
; Initialize the random number generator
;
INITRNG         .proc
                PHP

                setas
                LDA @l RTC_SEC              ; Get the seconds and minutes to use as a seed
                XBA
                LDA @l RTC_MIN

                setal
                STA @l GABE_RNG_DAT_LO      ; Set the seed

                setas
                LDA #GABE_RNG_CTRL_EN | GABE_RNG_CTRL_DV
                STA @l GABE_RNG_CTRL

                LDA #GABE_RNG_CTRL_EN
                STA @l GABE_RNG_CTRL

                PLP
                RTS
                .pend

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
; Initialize the graphics
;
INITGRAPH       PHP

                ; Turn on graphics, sprites, and tiles
                setas
                LDA #Mstr_Ctrl_Graph_Mode_En | Mstr_Ctrl_Sprite_En | Mstr_Ctrl_TileMap_En ;| Mstr_Ctrl_Text_Overlay | Mstr_Ctrl_Text_Mode_En
                STA @l MASTER_CTRL_REG_L

                LDA #%00000001                  ; Enable and use LUT0
                STA @l SP00_CONTROL_REG         ; With sprite #0

                LDA #0                          ; Turn off the border
                STA @l BORDER_CTRL_REG
                STA @l BORDER_X_SIZE            ; And set its size to 0
                STA @l BORDER_Y_SIZE

                LDA #0
                STA @l MOUSE_PTR_CTRL_REG_L     ; Turn off the mouse pointer

                setal
                LDA #640-32                     ; Set the right most position of a sprite
                STA BOUNDARY_R

                LDA #480-32                     ; Set the right most position of a sprite
                STA BOUNDARY_B

                PLP
                RTS

;
; Initialize the star field
;
INITSTARS       .proc
                PHP

                setal                                       ; Set the address of the tile set
                LDA #<>VSTARS
                STA @l TL0_START_ADDY_L
                setas
                LDA #(`VSTARS) - $B0
                STA @l TL0_START_ADDY_H

                LDA #%10000011                              ; Display the tiles and expect a 256x256 tile sheet
                STA @l TL0_CONTROL_REG

                LDX #0
loop            LDA @l GABE_RNG_SEED_LO                     ; Get a random number
                AND #$0F                                    ; Restrict it to 0 - 7
                BNE set_clear

                LDA @l GABE_RNG_SEED_LO                     ; Get a random number
                AND #$0F

set_tile        STA @l TILE_MAP0,X                          ; Save it to the tile map
                INX                                         ; Move to the next tile
                CPX #$0800                                  ; Until we've done the last tile
                BNE loop

                PLP
                RTS

set_clear       LDA #0                                      ; Most of tiles will be clear
                BRA set_tile
                .pend

;
; Initialize the player sprite
;
INITPLAYER      .proc
                PHP

                setal
                LDA #<>SP00_CONTROL_REG     ; Set the address of the sprite registers
                STA SHIP.SPRITEADDR

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

;;
;; Torpedo
;;

;
; Initialize the torpedo sprite
;
INITTORPEDO     .proc
                PHP

                setal
                LDA #<>SP01_CONTROL_REG     ; Set the address of the sprite registers
                STA TORPEDO.SPRITEADDR

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

;;
;; General Sprite Code
;;

;
; Animate all the sprites that are active
;
ANIMATE         .proc
                PHP

                setaxl
                LDX #<>START_OF_SPRITES
loop            JSR ANIMSPRITE
                TXA
                CLC
                ADC #size(SPRITE)
                TAX
                CPX #<>END_OF_SPRITES
                BNE loop

done            PLP
                RTS
                .pend

;
; Jump to the subroutine in the current program bank who's address is at INDPROC
;
DISPATCH        JMP (INDPROC)

;
; Animate a sprite
;
; Input:
;   X = address of the sprite record in bank 0
;
ANIMSPRITE      .proc
                PHP

                setdbr 0
                setdp SRCPTR

                setas
                LDA SPRITE.STATUS,X         ; Check if the sprite is active
                BPL done                    ; NO: there is no need to animate

                setaxl
                LDA SPRITE.ANIMPROC,X       ; Get the address of this sprite's animation routine
                BEQ do_frame                ; If it's NULL, just do the default stuff
                STA INDPROC                 ; Save it to the dispatch pointer
                JSR DISPATCH                ; And call it

do_frame        LDA SPRITE.FRAME,X          ; Get the current frame number
                BMI done                    ; If it's negative, the sprite is inactive

                ; Update the current frame to display for the sprite

                DEC SPRITE.FRAMEDELAY,X     ; Decrement the frame delay counter
                BNE frame_done              ; If it's not zero, we don't change the frame

                LDA SPRITE.DELAYDEFAULT,X   ; Reset the frame delay counter
                STA SPRITE.FRAMEDELAY,X

                LDA SPRITE.FRAME,X          ; Get the current frame number
                INC A                       ; Go to the next frame
                CMP SPRITE.FRAMECOUNT,X     ; Check to see if we've reached the limit
                BNE set_frame

                LDA #0                      ; Yes: return to frame 0
set_frame       STA SPRITE.FRAME,X          ; Set the frame

frame_done      ; Update the position of the sprite based on (DX, DY)

                DEC SPRITE.MOVEDELAY,X      ; Decrement the movement delay counter
                BNE done                    ; If it's not zero, we don't move the sprite

                LDA SPRITE.MOVEDELDEF,X     ; Reset the movement delay counter
                STA SPRITE.MOVEDELAY,X

                CLC                         ; X := X + DX
                LDA SPRITE.DX,X
                ADC SPRITE.X,X
                STA SPRITE.X,X

update_y        CLC                         ; Y := Y + DY
                LDA SPRITE.DY,X
                ADC SPRITE.Y,X
                STA SPRITE.Y,X

done            SEI                         ; Flag that the sprite needs to be updated in Vicky
                setas
                LDA #SP_STAT_UPDATE
                ORA SPRITE.STATUS,X
                STA SPRITE.STATUS,X

                PLP
                RTS
                .pend

;
; Update all the sprites that are active
;
UPDATE         .proc
                PHP

                setaxl
                LDX #<>START_OF_SPRITES
loop            JSR UPDATESPRITE
                TXA
                CLC
                ADC #size(SPRITE)
                TAX
                CPX #<>END_OF_SPRITES
                BNE loop

done            PLP
                RTS
                .pend

;
; Update the hardware sprite registers from a given sprite record
;
; Inputs:
;   X = address of the sprite record in bank 0
;
UPDATESPRITE    .proc
                PHP

                setdbr 0
                setdp SRCPTR

                setaxl

                LDA SPRITE.FRAME,X          ; Get the current frame number
                BMI done                    ; If it's negative, the sprite is inactive

                LDA SPRITE.SPRITEADDR,X     ; TMPPTR := pointer to the sprite's registers in Vicky
                STA REGPTR
                LDA #`SP00_CONTROL_REG
                STA REGPTR+2

                STZ TEMP
                STZ TEMP+2

                LDA SPRITE.X,X          ; Set the X position of the sprite
                LDY #SP_OFF_X
                STA [REGPTR],Y

                LDA SPRITE.Y,X          ; Set the Y position of the sprite
                LDY #SP_OFF_Y
                STA [REGPTR],Y

                LDA SPRITE.FRAME,X      ; Get the animation frame's offset into TEMP
                STA TEMP
                .rept 10
                ASL TEMP
                ROL TEMP+2
                .next

                CLC
                LDA SPRITE.BASEADDR,X   ; Add the base address of the animation frames
                ADC TEMP
                LDY #SP_OFF_ADDR
                STA [REGPTR],Y
                STA TEMP
                setas
                LDA SPRITE.BASEADDR+2,X
                ADC TEMP+2
                STA TEMP+2
                LDY #SP_OFF_ADDR+2
                STA [REGPTR],Y          ; And set the address of the sprite pixmap

done            PLP
                RTS
                .pend

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

                .include "interrupts.s"
                .include "tones.s"
                .include "rsrc/colors.s"         ; Load the LUT for the game
.send

                * = $110000
                .include "rsrc/spaceship_stationary.s"
                .include "rsrc/spaceship1_pix.s"
                .include "rsrc/startiles.s"
                .include "rsrc/torpedo.s"
                .include "rsrc/tone_pew.s"


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
VPURPLE = VTORPEDO + 8*32*32        ; Address in VRAM of the purple flier image data
VSTARS = VPURPLE + 2*32*32          ; Address of the star field tiles in VRAM

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
START_POOL = *                      ; First of the available sprites
ENEMY           .dstruct SPRITE     ; The enemy ship
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
                LDA #$FF                ; Set the noise volume to -1 as a sentinel value
                STA NOISEVOL

                setaxl

                SEI                     ; Turn off interrupts
                JSR INITRNG             ; Initialize the random number generator
                JSR LOADRSRC            ; Load the resources into video memory
                JSR INITGRAPH           ; Set up the graphics
                JSR INITTONE            ; Initialize the tone player engine
                JSR INITSTARS           ; Initialize the star field
                JSR INITSPRITES         ; Do initial setup of sprites
                JSR INITPLAYER          ; Initialize the player sprite
                JSR INITTORPEDO         ; Initialize the torpedo sprite
                JSR UPDATE
                JSR INITIRQ             ; Set up interrupts
                CLI                     ; Turn interrupts back on

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
; Initialize the sprite records
;
INITSPRITES     .proc
                PHP

                setdbr 0
                setdp SRCPTR

                setaxl
                LDX #<>START_OF_SPRITES
                LDA #<>SP00_CONTROL_REG

loop            STA SPRITE.SPRITEADDR,X         ; Set the address of the hardware sprite registers
                CLC                             ; Point to the next hardware sprite register set
                ADC #8                          ; <>(SP01_CONTROL_REG - SP00_CONTROL_REG)
                STA TEMP                        ; Save the address to temporary

                STZ SPRITE.X,X                  ; Zero out most of the parameters
                STZ SPRITE.Y,X
                STZ SPRITE.DX,X
                STZ SPRITE.DY,X
                STZ SPRITE.BASEADDR,X
                STZ SPRITE.BASEADDR+2,X
                STZ SPRITE.FRAME,X
                STZ SPRITE.FRAMECOUNT,X
                STZ SPRITE.FRAMEDELAY,X
                STZ SPRITE.DELAYDEFAULT,X
                STZ SPRITE.MOVEDELAY,X
                STZ SPRITE.MOVEDELDEF,X
                STZ SPRITE.ANIMPROC,X

                setas
                STZ SPRITE.STATUS,X             ; Set status to 0
                setal

                TXA                             ; Point to the next sprite record
                CLC
                ADC #SIZE(SPRITE)
                TAX

                LDA TEMP                        ; Get the address of the next sprite register block
                CPX #<>END_OF_SPRITES           ; Check to see if we've reached the end
                BNE loop                        ; No: keep initializing

                PLP
                RTS
                .pend

;
; Find an inactive sprite record
;
; Returns
;   X = pointer to the sprite record
;   Carry set if inactive record found, clear if all are in use.
;
FINDSPRITE      .proc
                PHP

                LDX #<>START_POOL

loop            setas
                LDA SPRITE.STATUS,X         ; Get the sprite's status
                BPL ret_true                ; If ACTIVE not set, we've got one

                setal                       ; If INACTIVE, move to the next reocrd
                TXA
                CLC
                ADC #SIZE(SPRITE)
                TAX

                CPX #<>END_OF_SPRITES       ; Have we checked all records?
                BNE loop                    ; No: keep checking

ret_false       PLP                         ; Return that we could not find a free sprite
                CLC
                RTS

ret_true        PLP                         ; Return that we found a free sprite
                SEC
                RTS
                .pend

                .include "interrupts.s"
                .include "tones.s"
                .include "resources.s"              ; The code to manage reading resource data
                .include "player.s"                 ; The code to manage the player and torpedo sprites
                .include "enemies.s"                ; The code to manage the enemy ships and weapons
                .include "rsrc/colors.s"            ; Load the LUT for the game
.send

                * = $110000
                .include "rsrc/spaceship_stationary.s"
                .include "rsrc/spaceship1_pix.s"
                .include "rsrc/startiles.s"
                .include "rsrc/torpedo.s"
                .include "rsrc/purple_flier.s"
                .include "rsrc/tone_pew.s"

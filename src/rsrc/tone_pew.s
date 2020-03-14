;;
;; The tone for a torpedo firing
;;

; C C G G A A G
; 261 261 392 392 440 400 392

TONE_PEW    
            TONE_OP TONE_SET_ATTEN, $F  ; SET ATTENUATION 0, 0
            TONE_FREQ 900               ; SET TONE 0, $0080
            TONE_OP TONE_START_ENV, 0   ; Start the envelope

            TONE_OP TONE_WAIT, 10       ; WAIT         

            TONE_FREQ 850               ; SET TONE 0, $0080
            TONE_OP TONE_WAIT, 1        ; WAIT

            TONE_FREQ 800               ; SET TONE 0, $0080
            TONE_OP TONE_WAIT, 1        ; WAIT

            TONE_FREQ 750               ; SET TONE 0, $0080
            TONE_OP TONE_WAIT, 1        ; WAIT

            TONE_FREQ 700               ; SET TONE 0, $0080
            TONE_OP TONE_WAIT, 1        ; WAIT

            TONE_FREQ 650               ; SET TONE 0, $0080
            TONE_OP TONE_WAIT, 1        ; WAIT

            TONE_OP TONE_RELEASE, 0     ; RELEASE
            TONE_OP TONE_FINISH, 0      ; FINISH

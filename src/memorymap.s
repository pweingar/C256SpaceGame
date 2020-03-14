;;;
;;; Define the major memory segments we'll use
;;;

; Global variable space
*=$002000
.dsection variables

; Where the main code will live
*=$003000
.dsection code

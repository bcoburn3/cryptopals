;this file is a re-write of my solutions to www.cryptopals.com, trying out cl21 and apps hungarian notation

(eval-when (:execute)
  (ql-dist:install-dist "http://dists.cl21.org/cl21.txt"))

(eval-when (:compile-toplevel :execute)
  (ql:quickload :cl21)
  (ql:quickload :cl-test-more)
  (ql:quickload "ironclad")
  (ql:quickload "hunchentoot")
  (ql:quickload :drakma)
  (ql:quickload :iterate))

(in-package :cl21-user)
(defpackage cryptopals 
  (:use :cl21
	:cl-test-more
	:iterate)
  (:shadowing-import-from :iterate :until)
  (:shadowing-import-from :iterate :while))
(in-package :cryptopals)

#|prefixes:
bv  -  byte vector
in  -  int
s   -  string
hs  -  hex string (eg, "12ef" for #x12ef)
hc  -  hex char
b64 -  base64 encoded data, represented as a string
cb  -  count of bytes
by  -  byte
?   -  boolean predicate

|#

;some utility functions
(defun bv-make (cb-length &optional by-initial-element)
  (if by-initial-element
      (make-array cb-length :element-type '(unsigned-byte 8) :initial-element by-initial-element)
      (make-array cb-length :element-type '(unsigned-byte 8) :initial-element 0)))

(defun bv-rand (cb-length)
  (ironclad:make-random-salt cb-length))

(defun bv-pad (bv padded-len)
  (concatenate 'vector (bv-make (- padded-len (length bv))) bv))

(defun bv-cat (&rest args)
  (apply #'concatenate 'vector args))

(defun bv-from-in (in)
   (iterate (for i first in then (/ (- i (mod i 256)) 256))
	    (while (>= i 1))
	    (with res = #())
	    (after-each (push (mod i 256) res))
	    (finally (return (nreverse res)))))

(defun bv-from-s (s)
  (map-to 'vector #'char-code s))

(defun bv-from-hs (hs)
  (let ((nibbles (map-to 'vector #'in-from-hc hs)))
    (let ((pairs (nreverse (subdivide (nreverse nibbles) 2)))) ;to handle odd lengths correctly
      (map-to 'vector (lm (pair) (+ (* 16 (second pair)) (first pair)))
	      pairs))))

(defun in-combine-bytes (high low bit-len)
  (+ (* high (expt 2 bit-len)) low))

(defun in-from-bv (bv)
  (reduce (lm (x y) (in-combine-bytes x y 8)) bv))

(defun in-from-s (s)
  (in-from-bv (bv-from-s s)))

(defun in-from-hc (hc)
  (let ((index "0123456789abcdef")
	(hc-dc (char-downcase hc)))
    (position hc-dc index)))

(defun in-from-hs (hs)
  (in-from-bv (bv-from-hs hs)))

(defun s-from-in (in)
  (s-from-bv (bv-from-in in)))

(defun s-from-bv (bv)
  (map-to 'string #'code-char bv))

(defun s-from-hs (hs)
  (s-from-bv (bv-from-hs hs)))

(defun s-from-seq (seq)
  (with-output-to-string (s)
    (doeach (x seq)
      (princ x s))))

(defun s-make (len &optional (c-initial-element #\a))
  (map-to 'string #'code-char (bv-make len (char-code c-initial-element))))

(defun s-cat (&rest args)
  (apply #'concatenate 'string args))

(defun hs-from-by (by)
  (let ((index "0123456789abcdef")
	(high (floor (/ by 16)))
	(low (mod by 16)))
    (format nil "~{~A~}" (list (getf index high) (getf index low)))))

(defun hs-from-bv (bv)
  (reduce (lm (x y) (s-cat x y)) 
	  (map-to 'list #'hs-from-by bv)))

(defun hs-from-in (in)
  (hs-from-bv (bv-from-in in)))

(defun hs-from-s (s)
  (hs-from-bv (bv-from-s s)))

;conversion function tests
(ok (equalp (bv-pad #(1 2) 3) #(0 1 2))
    "bv-pad")
(ok (equalp (bv-from-in 258) #(1 2))
    "bv-from-in 1")
(ok (equalp (bv-from-in 123) #(123))
    "bv-from-in 2")
(ok (equalp (bv-from-s "ab") #((char-code #\a) (char-code #\b)))
    "bv-from-s")
(is (in-from-bv #(1 2)) 258)
(is (in-from-hc #\a) 10)
(is (in-from-hs "BC614e") 12345678)
(is (s-from-seq '(#\a #\b #\c #\d #\e #\f)) "abcdef")
(is (s-from-seq #(#\a #\b #\c #\d #\e #\f)) "abcdef")
(is (hs-from-by 255) "ff")
(is (hs-from-bv #(255 0)) "ff00")
(is (s-from-in (+ (* 97 256) 98)) "ab")

;set 1

;1. Convert hex to base64 encoding.  Base64 will be represented as a string in all future cases in this file

(defun mod-remainder (num div)
  (if (= (mod num div) 0)
      0
      (- div (mod num div))))
  
(defun b64c-from-6bits (n)
  (let ((base64-index "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"))
        (getf base64-index n)))

(defun b64-from-3bytes (bv)
  (let ((len-pad (mod-remainder (length bv) 3)))
    (let ((in-padded (in-from-bv (bv-cat bv (bv-make len-pad))))
	  (s-padding (s-from-bv (bv-make len-pad 61))))
	(iterate (for offset in '(0 6 12 18))
		 (for cur-bits = (ldb (byte 6 offset) in-padded))
		 (collecting (b64c-from-6bits cur-bits) into l-res)
		 (finally (return (s-cat
					       (subseq (s-from-seq (nreverse l-res))
						       0
						       (- 4 len-pad))
					       s-padding)))))))

(defun b64-from-bv (bv)
  (s-from-seq (map #'b64-from-3bytes (subdivide bv 3))))

(defun b64-from-hs (hs)
  (b64-from-bv (bv-from-hs hs)))

(defun b64-from-s (s)
  (b64-from-bv (bv-from-s s)))

(defun b64-from-in (in)
  (b64-from-bv (bv-from-in in)))

(is (b64-from-s "l pleasure.") "bCBwbGVhc3VyZS4=")

(defun 6bits-from-b64c (b64c)
  (position b64c "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"))

(defun 3bv-from-b64 (b64)
  (let ((len-pad 0))
    (cond ((equalp (getf b64 2) #\=) (setf len-pad 2))
	  ((equalp (getf b64 3) #\=) (setf len-pad 1)))
    (let ((b64-padding (s-make len-pad #\A))
	  (b64-without-pad (subseq b64 0 (- 4 len-pad))))
      (let ((in-total (reduce (lm (high low) (in-combine-bytes high low 6))
			      (map-to 'vector #'6bits-from-b64c (s-cat b64-without-pad b64-padding)))))
	(subseq (bv-pad (bv-from-in in-total) 3) 0 (- 3 len-pad))))))
    
(defun bv-from-b64 (b64)
  (reduce #'append (map-to 'vector #'3bv-from-b64 (subdivide b64 4))))

(defun in-from-b64 (b64)
  (in-from-bv (bv-from-b64 b64)))

(defun s-from-b64 (b64)
  (s-from-bv (bv-from-b64 b64)))

(defun hs-from-b64 (b64)
  (hs-from-bv (bv-from-b64 b64)))

(defun bv-from-b64-file (file-name)
  (bv-from-b64 (remove #\Newline (remove #\Return (read-file-into-string file-name)))))

(is (b64-from-hs "49276d206b696c6c696e6720796f757220627261696e206c696b65206120706f69736f6e6f7573206d757368726f6f6d")
    "SSdtIGtpbGxpbmcgeW91ciBicmFpbiBsaWtlIGEgcG9pc29ub3VzIG11c2hyb29t")

;2. Fixed XOR

;(int-to-hex-string (hex-string-xor "1c0111001f010100061a024b53535009181c" "686974207468652062756c6c277320657965"))

;output: "746865206b696420646f6e277420706c6179"

(defun bv-xor (bv1 bv2)
  (map-to 'vector #'logxor bv1 bv2))

(defun hs-xor (hs1 hs2)
  (hs-from-bv (bv-xor (bv-from-hs hs1) (bv-from-hs hs2))))

(defun s-xor (s1 s2)
  (s-from-bv (bv-xor (bv-from-s s1) (bv-from-s s2))))

(defun int-xor (&rest ints)
  (apply #'logxor ints))

(is (hs-xor "1c0111001f010100061a024b53535009181c" "686974207468652062756c6c277320657965")
    "746865206b696420646f6e277420706c6179")

;3. Single-character XOR Cipher:


;frequency table derived from http://www.data-compression.com/english.html
(defvar *frequency-table* #H(#\a .0651738 #\b .0124248 #\c .0217339 #\d .0349835 #\e .1041442 #\f .0197881 #\g .0158610 #\h .049288 #\i .0558094 #\j .0009033 #\k .0050529 #\l .0331490 #\m .0202124 #\n .0564513 #\o .0596302 #\p .0137645 #\q .0008606 #\r .0497563 #\s .0515760 #\t .0729357 #\u .0225134 #\v .0082903 #\w .0171272 #\x .0013692 #\y .0145984 #\z .0007836 #\  .1918182 #\newline .01 #\Return .01 #\' .01 #\. .01 #\" .01 #\, .01 #\0 .001 #\1 .001 #\2 .001 #\3 .001 #\4 .001 #\5 .001 #\6 .001 #\7 .001 #\8 .001 #\9 .001))

#|
;frequency table derived from Vanilla Ice lyrics
(defvar *frequency-table* #H(#\! 1/3101 #\1 1/3101 #\0 1/3101 #\. 2/3101 #\5 1/3101 #\z 3/3101 #\q 2/3101 #\j 13/3101 #\- 2/3101 #\x 4/3101 #\u 62/3101 #\? 3/3101 #\f 29/3101 #\m 66/3101 #\w 6/443 #\d 11/443 #\n 137/3101 #\h 109/3101 #\g 51/3101 #\r 78/3101 #\a 204/3101 #\b 76/3101 #\c 107/3101 #\k 47/3101 #\s 110/3101 #\' 33/3101 #\t 173/3101 #\e 257/3101 #\l 151/3101 #\Newline 110/3101 #\p 47/3101 #\i 207/3101 #\v 36/3101 #\  526/3101 #\, 72/3101 #\o 179/3101 #\y 82/3101))
|#

(defun ft-from-string (s)
  (let ((ft #H()))
    (doeach (chr s)
      (inc-hash ft (char-downcase chr)))
    (ft-normalize-hash ft)))

(defun ft-from-file (file)
  (let ((s (read-file-into-string file)))
    (ft-from-string s)))

(defun ft-from-bv (bv)
  (ft-from-string (s-from-bv bv)))

(defun inc-hash (table key)
  (let ((?-exists (nth-value 1 (getf table key))))
    (if ?-exists
        (incf (getf table key))
      (setf (getf table key) 1))))

(defun ft-normalize-hash (ft)
  (let ((sum (reduce #'+ (map-to 'list #'cdr ft))))
    (doeach ((key val) ft)
      (setf (getf ft key) (/ val sum)))
    ft))

(defun fl-frequency-compare (ft-test ft-ref)
  (let ((res 0))
    (doeach ((key val) ft-test res)
      (if (getf ft-ref key)
	  (incf res (expt (abs (- val (getf ft-ref key))) 5))
	  (incf res 100)))))

(defun bv-xor-with-byte (bv by)
  (map (lm (x) (logxor x by)) bv))

(defun xor-crack (bv-ciphertext ft-ref)
  (let ((res (list "default result" 0 1000)))
    (doeach (x (iota 256) res)
      (let ((cand (fl-frequency-compare (ft-from-bv (bv-xor-with-byte bv-ciphertext x))
					ft-ref)))
	(if (< cand (nth res 2))
	    (setf res (list (s-from-bv (bv-xor-with-byte bv-ciphertext x)) x cand)))))))

(is (nth (xor-crack (bv-from-hs "1b37373331363f78151b7f2b783431333d78397828372d363c78373e783a393b3736") *frequency-table*) 0)
    "Cooking MC's like a pound of bacon")

;4. Detect single-character XOR

(defun slist-from-file (file-name)
  (let ((s-file (read-file-into-string file-name)))
    (split #\newline s-file)))

(defun xor-find-crack (slist-cipher ft-ref)
  (let ((res (list "default result" 0 1000)) ;must match the layout of the output from xor-crack above
	(slist-plain (map (lm (x) (xor-crack (bv-from-hs x) ft-ref)) slist-cipher)))
    (doeach (x slist-plain res)
      (if (< (nth x 2) (nth res 2))
		 (setf res x)))))

(defun file-xor-find-crack (file-name ft-ref)
  (nth (xor-find-crack (slist-from-file file-name) ft-ref) 0))

(ok (equalp (file-xor-find-crack "/home/adminuser/4.txt" *frequency-table*) 
	    "Now that the party is jumping\n")
    "file-xor-find-crack")

;5. Repeating-key XOR Cipher

(defun repeated-key-xor (bv-plain bv-key)
  (let ((bv-split (subdivide bv-plain (length bv-key))))
    (apply #'append (map-to 'list (lm (x) (bv-xor x bv-key)) bv-split))))

(is (hs-from-bv (repeated-key-xor (bv-from-s "Burning 'em, if you ain't quick and nimble I go crazy when I hear a cymbal")
				  (bv-from-s "ICE")))
    "0b3637272a2b2e63622c2e69692a23693a2a3c6324202d623d63343c2a26226324272765272a282b2f20690a652e2c652a3124333a653e2b2027630c692b20283165286326302e27282f")

;6. Break repeating-key XOR:

;(file-xor-crack "c:\\temp\\xor.txt" dict)

;outputs "Terminator X: Bring the noise" as the key, and some terrible vanila ice song as the plain text.

(defun in-bit-distance (in1 in2)
  (expt (logcount (logxor in1 in2)) 1))

(defun fl-bit-distance (bv1 bv2)
  (/ (reduce #'+ (map-to 'vector #'in-bit-distance bv1 bv2))
     (length bv1)))

(is (fl-bit-distance (bv-from-s "this is a test") (bv-from-s "wokka wokka!!!")) 37/14)

(is (fl-bit-distance #(2 4 8) #(3 5 9)) 1)
(is (fl-bit-distance #(2 4) #(3 5)) 1)

(defun map-pairs (fn seq)
  ;todo:  make this a generic function or something, so that the output type matches the
  ;       input type, instead of always outputing a list
  (iterate (repeat (- (length seq) 1))
	   (for elem first (first seq) then (first rest))
	   (for rest first (subseq seq 1) then (subseq rest 1))
	   (appending (map-to 'list (lm (x) (funcall fn x elem)) rest))))

(is (map-pairs #'+ '(1 2 3 4)) '(3 4 5 5 6 7))
(is (map-pairs #'+ #(1 2 3 4)) '(3 4 5 5 6 7))

(defun fact (in)
  (reduce #'* (iota in :start 1)))

(is (fact 1) 1)
(is (fact 5) 120)

(defun n-choose-r (n r)
  (/ (fact n) (* (fact r) (fact (- n r)))))

(is (n-choose-r 6 2) 15)

(defun lst-xor-block-size (bv-cipher max-size)
  (let ((lens (iota max-size :start 1)))
    (let ((cands (map (lm (x) (xor-block-size-helper bv-cipher x))
		      lens)))
      (take 15 (sort cands (lm (pair1 pair2) (< (cdr pair1) (cdr pair2))))))))
  
(defun xor-block-size-helper (bv-cipher len)
  (let ((blocks (subdivide bv-cipher len)))
    (cons len
	  (/ (reduce #'+ (map-pairs #'fl-bit-distance blocks))
	     (n-choose-r (length blocks) 2)))))
	
(defun lst-block-transpose (bv block-len)
  (let ((res '())
	(blocks (subdivide bv block-len)))
    (doeach (i (iota block-len) res)
      (push (map-to 'vector (lm (x) (if (< i (length x)) (elt x i) 0)) blocks) res))
    (nreverse res)))

(ok (equalp (lst-block-transpose #(1 2 3 4 5 6 7 8) 2) 
	    (list (vector 1 3 5 7) (vector 2 4 6 8)))
    "lst-block-transpose")

(defun bv-find-repeat-key (bv-cipher)
 (let* ((block-lens (map #'car (lst-xor-block-size bv-cipher 50)))
	(transposes (map (lm (x) (lst-block-transpose bv-cipher x)) block-lens)))
    (let* ((lst-keys (map (lm (transpose) (map-to 'vector (lm (bv) (elt (xor-crack bv *frequency-table*) 1))
						 transpose))
			  transposes))
	   (lst-bvs (map (lm (key) (repeated-key-xor bv-cipher key))
			 lst-keys)))
      (car (sort lst-bvs (lm (bv1 bv2) (< (fl-frequency-compare (ft-from-bv bv1) *frequency-table*)
					  (fl-frequency-compare (ft-from-bv bv2) *frequency-table*))))))))

(defun s-file-find-repeat-key (filename)
  (s-from-bv (bv-find-repeat-key (bv-from-b64-file filename))))

(eval-when (:execute)
  (print (s-file-find-repeat-key "c:\\temp\\xor.txt")))

(eval-when (:execute)
  (print (s-file-find-repeat-key "/home/adminuser/6.txt")))
	 
;7. AES in ECB mode:

(defun bv-AES-encrypt (bv-msg bv-key)
  (let ((bv-res (bv-make (length bv-msg)))
	(cipher (ironclad:make-cipher :AES :mode :ECB :key (coerce bv-key '(vector (unsigned-byte 8))))))
    (ironclad:encrypt cipher (coerce bv-msg '(vector (unsigned-byte 8))) bv-res)
    bv-res))

(defun bv-AES-decrypt (bv-msg bv-key)
  (let ((bv-res (bv-make (length bv-msg)))
	(cipher (ironclad:make-cipher :AES :mode :ECB :key (coerce bv-key '(vector (unsigned-byte 8))))))
    (ironclad:decrypt cipher (coerce bv-msg '(vector (unsigned-byte 8))) bv-res)
    bv-res))

(defun s-AES-encrypt (s-msg s-key)
  (let ((bv-msg (bv-from-s s-msg))
	(bv-key (bv-from-s s-key)))
    (s-from-bv (bv-aes-encrypt bv-msg bv-key))))

(defun s-AES-decrypt (s-msg s-key)
  (let ((bv-msg (bv-from-s s-msg))
	(bv-key (bv-from-s s-key)))
    (s-from-bv (bv-aes-decrypt bv-msg bv-key))))

(defun bv-file-aes-encrypt (file-name bv-key)
  (let ((bv-msg (bv-from-s (read-file-into-string file-name))))
    (bv-aes-encrypt bv-msg bv-key)))

(defun bv-file-aes-decrypt (file-name bv-key)
  (let ((bv-msg (bv-from-s (read-file-into-string file-name))))
    (bv-aes-decrypt bv-msg bv-key)))

(defun s-file-aes-encrypt (file-name s-key)
  (let ((bv-key (bv-from-s s-key)))
    (s-from-bv (bv-file-aes-encrypt file-name bv-key))))

(defun s-file-aes-decrypt (file-name s-key)
  (let ((bv-key (bv-from-s s-key)))
    (s-from-bv (bv-file-aes-decrypt file-name bv-key))))

(eval-when (:execute)
  (print (s-from-bv (bv-aes-decrypt (bv-from-b64-file "/home/adminuser/7.txt") (bv-from-s "YELLOW SUBMARINE")))))

;8. Detect AES in ECB mode

;this is easy.  The only distinguishing fact about ECB is that identical blocks give identical encryption, so look for identical blocks

(defun bv-find-duplicate-blocks (lst-bvs cb-len)
  (let ((lst-blocks (map (lm (bv) (subdivide bv cb-len)) lst-bvs))
	(res #()))
    (doeach (blocks lst-blocks res)
      (if (not (= (reduce #'+ (map-pairs #'fl-bit-distance blocks)) 0))
	  (setf res (apply #'bv-cat blocks))))))

(defun bv-file-find-duplicate-blocks (file-name cb-len)
  (let* ((lst-hs (split #\newline (read-file-into-string file-name)))
	 (lst-bvs (map #'bv-from-hs lst-hs)))
    (bv-find-duplicate-blocks lst-bvs cb-len)))

(eval-when (:execute)
  (print (bv-file-find-duplicate-blocks "/home/adminuser/8.txt" 16)))


;problems from set 2

;9. Implement PKCS#7 padding

(defun bv-pkcs7-pad (bv cb-block-len)
  ;gives a full block of padding for even multiples of the block length
  (let ((cb-padding-len (- cb-block-len (mod (length bv) cb-block-len))))
    (bv-cat bv (make-array cb-padding-len :initial-element cb-padding-len))))

(ok (equalp (bv-pkcs7-pad (bv-from-s "YELLOW SUBMARINE") 20) 
	    #(89 69 76 76 79 87 32 83 85 66 77 65 82 73 78 69 4 4 4 4))
    "bv-pkcs7-pad 1")

(ok (equalp (bv-pkcs7-pad (bv-from-s "YELLOW SUBMARINE") 16)
	       #(89 69 76 76 79 87 32 83 85 66 77 65 82 73 78 69 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16))
    "bv-pkcs7-pad 2")

;this is nominally challenge 15, but using it makes #13 easier to implement, so I'm writing it now
(defun bv-pkcs7-unpad (bv cb-block-len)
  ;returns nil for invalid padding
  (iterate (for i from 1)
	   (until (equalp (subseq bv (- (length bv) i)) (bv-make i i)))
	   (until (> i cb-block-len))
	   (finally (if (<= i cb-block-len)
			(return (subseq bv 0 (- (length bv) i)))
			(return 'nil)))))

(ok (equalp (bv-pkcs7-unpad (bv-pkcs7-pad (bv-from-s "YELLOW SUBMARINE") 20) 20)
	    (bv-from-s "YELLOW SUBMARINE"))
    "bv-pkcs7-unpad 1")

(ok (equalp (bv-pkcs7-unpad #(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16) 16)
	    'nil)
    "bv-pkcs7-unpad 2")

(defun bv-aes-pkcs7-encrypt (bv-msg bv-key)
  (bv-aes-encrypt (bv-pkcs7-pad bv-msg 16) bv-key))

(defun bv-aes-pkcs7-decrypt (bv-msg bv-key)
  (bv-aes-decrypt (bv-pkcs7-unpad bv-msg 16) bv-key))

;10. Implement CBC Mode

(defun bv-aes-cbc-encrypt (bv-msg bv-iv bv-key)
  (let* ((bv-padded (bv-pkcs7-pad bv-msg 16))
	 (blocks (subdivide bv-padded 16))
	 (res (iterate (for next in blocks)
		       (for prev previous ctext initially bv-iv)
		       (for ctext = (bv-aes-encrypt (bv-xor prev next) bv-key))
		       (collecting ctext))))
    (apply #'bv-cat res)))

(defun bv-aes-cbc-decrypt (bv-msg bv-iv bv-key)
  (let* ((blocks (subdivide bv-msg 16))
	 (res (iterate (for next in blocks)
		       (for prev previous next initially bv-iv)
		       (collecting (bv-xor (bv-aes-decrypt next bv-key) prev)))))
    (bv-pkcs7-unpad (apply #'bv-cat res) 16)))

(defun bv-file-aes-cbc-encrypt (file-name bv-iv bv-key)
  (let ((bv-msg (bv-from-b64-file file-name)))
    (bv-aes-cbc-encrypt bv-msg bv-iv bv-key)))

(defun s-file-aes-cbc-encrypt (file-name s-iv s-key)
  (let ((bv-iv (bv-from-s s-iv))
	(bv-key (bv-from-s s-key)))
    (s-from-bv (bv-file-aes-cbc-encrypt file-name bv-iv bv-key))))

(defun bv-file-aes-cbc-decrypt (file-name bv-iv bv-key)
  (let ((bv-msg (bv-from-b64-file file-name)))
    (bv-aes-cbc-decrypt bv-msg bv-iv bv-key)))

(defun s-file-aes-cbc-decrypt (file-name s-iv s-key)
  (let ((bv-iv (bv-from-s s-iv))
	(bv-key (bv-from-s s-key)))
    (s-from-bv (bv-file-aes-cbc-decrypt file-name bv-iv bv-key))))

(ok (equalp (let ((bv-msg (bv-make 48 65))
		  (bv-key (bv-rand 16))
		  (bv-iv (bv-rand 16)))
	      (bv-aes-cbc-decrypt (bv-aes-cbc-encrypt bv-msg bv-iv bv-key) bv-iv bv-key))
	    (bv-make 48 65))
    "bv-aes-cbc-encrypt/decrypt")


;11. An ECB/CBC detection oracle

;This is also easy:  just send a long repeated string as input, check for repeats in the output

(defmacro with-cbc-keys ((sym-iv sym-key) &body body)
  `(let ((,sym-iv (bv-rand 16))
	 (,sym-key (bv-rand 16)))
     ,@body))

(defun ch11-oracle (bv-msg)
  (let ((bv-pre-pad (bv-rand (+ 5 (random 6))))
	(bv-post-pad (bv-rand (+ 5 (random 6)))))
    (with-cbc-keys (bv-iv bv-key)
      (let ((bv-padded (bv-cat bv-pre-pad bv-msg bv-post-pad)))
	(if (= (random 2) 0)
	    (progn (print "cbc")
		   (bv-aes-cbc-encrypt bv-padded bv-iv bv-key))
	    (progn (print "ecb")
		   (bv-aes-encrypt bv-padded bv-key)))))))

(defun ?-duplicate-blocks (blocks)
  (some (lm (x) (= x 0)) (map-pairs #'fl-bit-distance blocks)))

(defun ch11-crack ()
  (let* ((bv-msg (bv-make 48 65))
	 (bv-res (coerce (ch11-oracle bv-msg) '(and common-lisp:vector (not simple-array))))
	 (blocks (subdivide bv-res 16)))
    (if (?-duplicate-blocks blocks)
	"ecb"
	"cbc")))

(print (ch11-crack))


;12. Byte-at-a-time ECB decryption (Simple)

(defun ch12-oracle (bv-msg)
  (let ((bv-post-pad (bv-rand (+ 5 (random 6))))
	(bv-secret (bv-from-b64 "Um9sbGluJyBpbiBteSA1LjAKV2l0aCBteSByYWctdG9wIGRvd24gc28gbXkgaGFpciBjYW4gYmxvdwpUaGUgZ2lybGllcyBvbiBzdGFuZGJ5IHdhdmluZyBqdXN0IHRvIHNheSBoaQpEaWQgeW91IHN0b3A/IE5vLCBJIGp1c3QgZHJvdmUgYnkK"))
	(bv-key (bv-rand 16)))
    (bv-aes-encrypt (bv-pkcs7-pad (bv-cat bv-msg bv-secret bv-post-pad) 16) bv-key)))

(defun ch12-crack ()
  (let ((bv-res #()))
    (iterate (for i upfrom 1)
	     (for cb-offset = (- 16 (mod i 16)))
	     (for bv-offset = (bv-make cb-offset))
	     (for bv-prefix first (bv-make 15) then (bv-cat (subseq bv-prefix 1) (vector by-res)))
	     (for by-res = (iterate (for i from 0 to 255)
				    (for bv-msg = (bv-cat bv-prefix (vector i) bv-offset)) 
				    (for bv-oracle-output = (ch12-oracle bv-msg))
				    (until (?-duplicate-blocks (subdivide bv-oracle-output 16)))
				    (finally (return i))))
	     (until (= by-res 256))
	     (after-each (push by-res bv-res))
	     (finally (return (s-from-bv bv-res))))))

(eval-when (:execute)
  (print (ch12-crack)))


;13.  ECB cut-and-paste

(defun ch13-parse (s-cookie)
  (let* ((s-pairs (split #\& s-cookie))
	 ;map doesn't work here, seems to give a list with slightly incorrect structure
	 (s-keys-vals (iterate (for s in s-pairs) 
			       (appending (split #\= s)))))
    (apply #'hash-table #'equal s-keys-vals)))

(defun ch13-make-profile (s-email)
  (let ((s-stripped (remove #\= (remove #\& s-email))))
    #"email=${s-stripped}&uid=10&role=user"))

(is (ch13-make-profile "foo@bar.com") "email=foo@bar.com&uid=10&role=user")

(defun ch13-test (bv-ctext bv-key)
  (let* ((s-cookie (s-from-bv (bv-pkcs7-unpad (bv-aes-decrypt bv-ctext bv-key) 16)))
	 (profile-table (ch13-parse s-cookie)))
    (if (equal (getf profile-table "role") "admin")
	"victory"
	"failure")))

(is (ch13-test (bv-aes-encrypt (bv-pkcs7-pad (bv-from-s "email=foo@bar.com&uid=10&role=admin") 16)
			       (bv-make 16)) (bv-make 16))
    "victory")

(defun ch13-enc-profile (s-email bv-key)
  (bv-aes-pkcs7-encrypt (bv-from-s (ch13-make-profile s-email)) bv-key))

(defun ch13-crack ()
  (let ((bv-key (bv-rand 16)))
    (let ((bv-padding (last (subdivide (ch13-enc-profile "fo@ba.com" bv-key) 16))) ;encryption of 16 16's
	  (bv-email (subseq (ch13-enc-profile "bcobu@foo.com" bv-key) 0 32))
	  (bv-admin (elt (subdivide (ch13-enc-profile "foo@bar.coadmin" bv-key) 16) 1)))
      (ch13-test (bv-cat bv-email bv-admin bv-padding) bv-key))))

(is (ch13-crack)
    "victory")


;14. Byte-at-a-time ECB decryption (Harder)

;this is identical to #12, except that there's an initial step where we find the length of the 'random' prefix
(defvar *ch14-prefix-len* (+ 5 (random 6)))

(defun ch14-oracle (bv-msg)
  (let ((bv-pre-pad (bv-rand *ch14-prefix-len*))
	(bv-post-pad (bv-rand (+ 5 (random 6))))
	(bv-secret (bv-from-b64 "Um9sbGluJyBpbiBteSA1LjAKV2l0aCBteSByYWctdG9wIGRvd24gc28gbXkgaGFpciBjYW4gYmxvdwpUaGUgZ2lybGllcyBvbiBzdGFuZGJ5IHdhdmluZyBqdXN0IHRvIHNheSBoaQpEaWQgeW91IHN0b3A/IE5vLCBJIGp1c3QgZHJvdmUgYnkK"))
	(bv-key (bv-rand 16)))
    (bv-aes-encrypt (bv-pkcs7-pad (bv-cat bv-pre-pad bv-msg bv-secret bv-post-pad) 16) bv-key)))

(defun ch14-prefix-len ()
  (iterate (for i from 0 to 16)
	   (for bv-oracle-output = (ch14-oracle (bv-cat (bv-rand i) (bv-make 32))))
	   (until (?-duplicate-blocks (subdivide bv-oracle-output 16)))
	   (finally (return i))))

(defun ch14-crack ()
  (let ((bv-res #())
	(cb-prefix-len (ch14-prefix-len)))
    (iterate (for i upfrom 1)
	     (for cb-offset = (- 16 (mod i 16)))
	     (for bv-offset = (bv-make cb-offset))
	     (for bv-prefix first (bv-make (+ cb-prefix-len 15)) then (bv-cat (subseq bv-prefix 1) (vector by-res)))
	     (for by-res = (iterate (for i from 0 to 255)
				    (for bv-msg = (bv-cat bv-prefix (vector i) bv-offset)) 
				    (for bv-oracle-output = (ch14-oracle bv-msg))
				    (until (?-duplicate-blocks (subdivide bv-oracle-output 16)))
				    (finally (return i))))
	     (until (= by-res 256))
	     (after-each (push by-res bv-res))
	     (finally (return (s-from-bv bv-res))))))

(eval-when (:execute)
  (print (ch14-crack)))


;15. PKCS#7 padding validation

;implementing above under #9, because it's used in #13


;16. CBC bitflipping attacks


(defun ch16-encrypt (s-userdata bv-iv bv-key)
  (let ((s-stripped (remove #\= (remove #\; s-userdata)))
	(s-pre "comment1=cooking%20MCs;userdata=")
	(s-post ";comment2=%20like%20a%20pound%20of%20bacon"))
    (let ((bv-msg (bv-from-s (s-cat s-pre s-stripped s-post))))
      (bv-aes-cbc-encrypt bv-msg bv-iv bv-key))))

(defun ch16-check (bv-ctext bv-iv bv-key)
  (let ((s-ptext (s-from-bv (bv-aes-cbc-decrypt bv-ctext bv-iv bv-key))))
    (search";admin=true;" s-ptext)))

(defun ch16-crack ()
  (with-cbc-keys (bv-iv bv-key)
    (let* ((bv-userdata (bv-make 16 65))
	   (bv-ctext (ch16-encrypt (s-from-bv bv-userdata) bv-iv bv-key))
	   (bv-target (bv-from-s "a;admin=true;aaa"))
	   (bv-edit (bv-xor (bv-xor bv-userdata bv-target) (subseq bv-ctext 16 32))))
      (ch16-check bv-ctext bv-iv bv-key)
      (ch16-check (bv-cat (subseq bv-ctext 0 16) bv-edit (subseq bv-ctext 32))
		  bv-iv
		  bv-key))))

(ok (ch16-crack) "Challenge 16")
  

;problems from set 3

;17. CBC padding oracle

(defun ch17-encrypt (bv-iv bv-key)
  (let ((lst-secrets (list "MDAwMDAwTm93IHRoYXQgdGhlIHBhcnR5IGlzIGp1bXBpbmc="
			   "MDAwMDAxV2l0aCB0aGUgYmFzcyBraWNrZWQgaW4gYW5kIHRoZSBWZWdhJ3MgYXJlIHB1bXBpbic="
			   "MDAwMDAyUXVpY2sgdG8gdGhlIHBvaW50LCB0byB0aGUgcG9pbnQsIG5vIGZha2luZw=="
			   "MDAwMDAzQ29va2luZyBNQydzIGxpa2UgYSBwb3VuZCBvZiBiYWNvbg=="
			   "MDAwMDA0QnVybmluZyAnZW0sIGlmIHlvdSBhaW4ndCBxdWljayBhbmQgbmltYmxl"
			   "MDAwMDA1SSBnbyBjcmF6eSB3aGVuIEkgaGVhciBhIGN5bWJhbA=="
			   "MDAwMDA2QW5kIGEgaGlnaCBoYXQgd2l0aCBhIHNvdXBlZCB1cCB0ZW1wbw=="
			   "MDAwMDA3SSdtIG9uIGEgcm9sbCwgaXQncyB0aW1lIHRvIGdvIHNvbG8="
			   "MDAwMDA4b2xsaW4nIGluIG15IGZpdmUgcG9pbnQgb2g="
			   "MDAwMDA5aXRoIG15IHJhZy10b3AgZG93biBzbyBteSBoYWlyIGNhbiBibG93")))
    (let ((bv-secret (bv-from-b64 (elt lst-secrets (random (length lst-secrets))))))
      (bv-aes-cbc-encrypt bv-secret bv-iv bv-key))))

(defun ch17-oracle (bv-msg bv-iv bv-key)
  (let ((res (bv-aes-cbc-decrypt bv-msg bv-iv bv-key)))
    (if res
	t
	'nil)))

(defun ch17-crack ()
  (with-cbc-keys (bv-iv bv-key)
    (let ((blocks (subdivide (ch17-encrypt bv-iv bv-key) 16)))
      (iterate (for bv-cur-block in blocks)
	       (for bv-cur-iv previous bv-cur-block initially bv-iv)
	       (collecting (bv-cbc-padding-block bv-cur-block bv-cur-iv bv-key)
			   into lst-res)
	       (finally (return (s-from-bv (bv-pkcs7-unpad (apply #'bv-cat lst-res) 16))))))))

(defun bv-cbc-padding-block (bv-block bv-iv bv-key)
  (iterate (for i from 1 to 16)
	   (with bv-mask-suffix = #())
	   (for by-cur =
		(iterate (for n from 0 to 255)
			 (for bv-xor-mask = (bv-cat 
							 (bv-make (- 16 i) 0)
							 #(n)
							 bv-mask-suffix))
			 (until (ch17-oracle (bv-cat bv-xor-mask bv-block)
					     bv-iv
					     bv-key))
			 (finally (return (logxor n i (elt bv-iv (- 16 i)))))))
	   (collecting by-cur into bv-res at beginning result-type 'vector)
	   (after-each (setf bv-mask-suffix (bv-xor (bv-xor (subseq bv-iv (- 16 i))
							    bv-res)
						    (bv-make i (+ i 1)))))
	   (finally (return bv-res))))

(eval-when (:execute)
  (print (ch17-crack)))

#! /usr/bin/env gsi

;;;============================================================================

;;; File: "runtests.scm"

;;; Copyright (c) 2012-2017 by Marc Feeley, All Rights Reserved.

;;;----------------------------------------------------------------------------

(define cleanup? #t)

(define nb-good 0)
(define nb-fail 0)
(define nb-other 0)
(define nb-total 0)
(define start 0)

(define (num->string num w d) ; w = total width, d = decimals
  (let ((n (floor (inexact->exact (round (* (abs num) (expt 10 d)))))))
    (let ((i (quotient n (expt 10 d)))
          (f (modulo n (expt 10 d))))
      (let ((si (string-append
                  (if (< num 0) "-" "")
                  (if (and (= i 0) (> d 0)) "" (number->string i 10))))
            (sf (number->string (+ f (expt 10 d)) 10)))
        (if (> d 0)
          (string-set! sf 0 #\.)
          (set! sf ""))
        (let ((lsi (string-length si))
              (lsf (string-length sf)))
          (let ((blanks (- w (+ lsi lsf))))
            (string-append (make-string (max blanks 0) #\space) si sf)))))))

(define (sort-list lst <?)

  (define (mergesort lst)

    (define (merge lst1 lst2)
      (cond ((null? lst1) lst2)
            ((null? lst2) lst1)
            (else
             (let ((e1 (car lst1)) (e2 (car lst2)))
               (if (<? e1 e2)
                 (cons e1 (merge (cdr lst1) lst2))
                 (cons e2 (merge lst1 (cdr lst2))))))))

    (define (split lst)
      (if (or (null? lst) (null? (cdr lst)))
        lst
        (cons (car lst) (split (cddr lst)))))

    (if (or (null? lst) (null? (cdr lst)))
      lst
      (let* ((lst1 (mergesort (split lst)))
             (lst2 (mergesort (split (cdr lst)))))
        (merge lst1 lst2))))

  (mergesort lst))

(define (show-bar nb-good nb-fail nb-other nb-total elapsed)

  (define (ratio n)
    (quotient (* n (+ nb-good nb-fail nb-other)) nb-total))

  (let* ((istty (tty? (current-output-port)))
         (bar-width 16)
         (bar-length (ratio bar-width)))

    (define (esc x)
      (if istty x ""))

    (print (if istty "\r" "\n")
           "["
           (esc "\33[32;1m") (num->string nb-good 3 0) (esc "\33[0m")
           "|"
           (esc "\33[31;1m") (num->string nb-fail 3 0) (esc "\33[0m")
           ;;"|"
           ;;(esc "\33[34;1m") (num->string nb-other 4 0) (esc "\33[0m")
           "] "
           (num->string (ratio 100) 3 0)
           "% "
           (make-string bar-length #\#)
           (make-string (- bar-width bar-length) #\.)
           " "
           (num->string elapsed 3 1)
           "s"
           (esc "\33[K"))

    (force-output)))

(define (run path . args)
  (let* ((port
          (open-process (list path: path
                              arguments: args
                              ;; stderr-redirection: #t
                              )))
         (output
          (read-line port #f))
         (status
          (process-status port)))
    (close-port port)
    (cons status output)))

(define (trim-filename file)
  (if (and (>= (string-length file) (string-length default-dir))
           (string=? (substring file 0 (string-length default-dir))
                     default-dir))
      (substring file (string-length default-dir) (string-length file))
      file))

(define (test file)

  (print " " (trim-filename file))
  (force-output)

  (let ((results (test-with-each-target file))
        (diff? #f))

    (for-each
     (lambda (x)
       (let ((target (car x))
             (result (cdr x)))

         ;;(pp result)
         ;;(pp (cdar results))

         (if (not (equal? result (cdar results)))
             (begin
               (if (not diff?)
                   (begin
                     (print "\n")
                     (print "*********************** FAILED TEST " file "\n")
                     (print "======================= EXPECTED:\n" (cdr (cdar results)))))
               (set! diff? #t)
               (print "======================= ")
               (write (cons (car target) (caddr target)))
               (print ":\n")
               (print (cdr result))
               #;(print (diff (car target) (cdr (cdar results)) (cdr result)))
               ))))
     (cdr results))

    (if diff?
        (set! nb-fail (+ nb-fail 1))
        (set! nb-good (+ nb-good 1)))

    (show-bar nb-good
              nb-fail
              nb-other
              nb-total
              (- (time->seconds (current-time)) start))))

(define (run-tests files)

  (set! nb-good 0)
  (set! nb-fail 0)
  (set! nb-other 0)
  (set! nb-total (length files))
  (set! start (time->seconds (current-time)))

  (show-bar nb-good nb-fail nb-other nb-total 0.0)

  (for-each test files)

  (print "\n")

  (if (= nb-good nb-total)
      (begin
        (print "PASSED ALL " nb-total " UNIT TESTS\n")
        (exit 0))
      (begin
        (print "FAILED " nb-fail " UNIT TESTS OUT OF " nb-total " (" (num->string (* 100. (/ nb-fail nb-total)) 0 1) "%)\n")
        (exit 1))))

(define (diff target-name target-output expected-output)
  (with-output-to-file "expected" (lambda () (print expected-output)))
  (with-output-to-file target-name (lambda () (print target-output)))
  (let ((d (run "diff" "-u" target-name "expected")))
    (delete-file target-name)
    (delete-file "expected")
    (cdr d)))

(define (test-with-each-target file)
  (map (lambda (t)
         (let ((target (car t))
               (ext (cadr t)))
           (cons t
                 (if ext
                     (let* ((file-no-ext (path-strip-extension file))
                            (out_ (string-append file-no-ext "_" ext))
                            (out (string-append file-no-ext ext)))

                       (if (not (equal? target "gambit"))
                           (compile file ext target (caddr t)))

                       (let ((result
                              (if (equal? target "java")
                                  (begin
                                    (run (string-append (path-directory (cadddr t)) "javac") out_ out)
                                    (apply run
                                           (append (cdddr t)
                                                   (list "-classpath"
                                                         (path-directory file-no-ext)
                                                         (string-append (path-strip-directory file-no-ext) "_")))))
                                  (apply run (append (cdddr t) (list out))))))

                         (if (not (equal? target "gambit"))
                             (if cleanup?
                                 (begin
                                   (if (not (equal? target "C"))
                                       (delete-file out_))
                                   (delete-file out)
                                   (if (equal? target "java")
                                       (parameterize ((current-directory
                                                       (path-directory out)))
                                         (shell-command "rm *.class"))))))

                         result))

                     (apply run (append (cdddr t) (list file)))))))
       (keep (lambda (t)
               (member (string->symbol (car t)) (cons 'C targets)))
             target-configs)))

(define (compile file ext target options)
  (let* ((file-no-ext
          (path-strip-extension file))
         (x
          (if (equal? target "C")
              (run "./gsc" "-:=.."                      file)
              (apply run
                     (append (list "./gsc" "-:=.." "-o" (path-directory file) "-target" target "-link" "-flat")
                             options
                             (list file))))))
    (if (not (= (car x) 0))
        (error "couldn't compile" file target))
    (if (and (not (equal? target "C"))
             (not (equal? target "java")))
        (begin
          (shell-command
           (string-append
            "cat "
            (string-append file-no-ext "_" ext)
            " "
            (string-append file-no-ext ext)
            " > "
            (string-append file-no-ext "_merged" ext)))
          (shell-command
           (string-append
            "mv "
            (string-append file-no-ext "_merged" ext)
            " "
            (string-append file-no-ext ext)))))))

(define target-configs
  '(
    ("gambit" ".scm"  ()
                      "./gsc" "-i")

    ("C"      ".o1"   ()
                      "./gsc" "-i")

    ("x86"    #f      ()
                      "./gsc32" "-:=.." "-target" "nat" "-c" "-e" "(load \"_t-x86.scm\")")

    ("x86-64" #f      ()
                      "./gsc64" "-:=.." "-target" "nat" "-c" "-e" "(load \"_t-x86.scm\")")

    ("java"   ".java" ()
                      "java")

    ("java"   ".java" ("-pre7")
                      "/Library/Java/JavaVirtualMachines/1.6.0.jdk/Contents/Commands/java")

    ("js"     ".js"   ()
                      "d8")

    ;; repr-module = globals
    ("js"     ".js"   ("-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "d8")
    ("js"     ".js"   ("-repr-module"    "globals"
                       "-repr-procedure" "class"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "d8")
    ("js"     ".js"   ("-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "class"
                      )
                      "d8")
    ("js"     ".js"   ("-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "host"
                      )
                      "d8")
    ;; repr-module = class
    ("js"     ".js"   ("-repr-module"    "class"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "d8")
    ("js"     ".js"   ("-repr-module"    "class"
                       "-repr-procedure" "class"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "d8")
    ("js"     ".js"   ("-repr-module"    "class"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "class"
                      )
                      "d8")
    ("js"     ".js"   ("-repr-module"    "class"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "host"
                      )
                      "d8")

    ("python" ".py"   ()
                      "python3")

    ;; repr-module = globals
    ("python" ".py"   ("-pre3"
                       "-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "python")
    ("python" ".py"   ("-pre3"
                       "-repr-module"    "globals"
                       "-repr-procedure" "class"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "python")
    ("python" ".py"   ("-pre3"
                       "-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "class"
                      )
                      "python")
    ("python" ".py"   ("-pre3"
                       "-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "host"
                      )
                      "python")

#|
    ;; repr-module = class
    ("python" ".py"   ("-pre3"
                       "-repr-module"    "class"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "python")
    ("python" ".py"   ("-pre3"
                       "-repr-module"    "class"
                       "-repr-procedure" "class"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "python")
    ("python" ".py"   ("-pre3"
                       "-repr-module"    "class"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "class"
                      )
                      "python")
    ("python" ".py"   ("-pre3"
                       "-repr-module"    "class"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "host"
                      )
                      "python")
|#
    ;; repr-module = globals
    ("python" ".py"   ("-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "python3")
    ("python" ".py"   ("-repr-module"    "globals"
                       "-repr-procedure" "class"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "python3")
    ("python" ".py"   ("-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "class"
                      )
                      "python3")
    ("python" ".py"   ("-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "host"
                      )
                      "python3")
#|
    ;; repr-module = class
    ("python" ".py"   ("-repr-module"    "class"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "python3")
    ("python" ".py"   ("-repr-module"    "class"
                       "-repr-procedure" "class"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "python3")
    ("python" ".py"   ("-repr-module"    "class"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "class"
                      )
                      "python3")
    ("python" ".py"   ("-repr-module"    "class"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "host"
                      )
                      "python3")
|#
#;
    ("ruby"   ".rb"   ()
                      "/usr/bin/ruby") ;; ruby 2.0.0p451
#;
    ("ruby"   ".rb"   ()
                      "/usr/local/Cellar/ruby/2.1.5/bin/ruby") ;; ruby 2.1.5
#;
    ("ruby"   ".rb"   ()
                      "/usr/local/bin/ruby") ;; ruby 1.9.3p392

    ;; repr-module = globals
    ("ruby"   ".rb"   ("-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "/usr/local/bin/ruby") ;; ruby 1.9.3p392
#|
    ("ruby"   ".rb"   ("-repr-module"    "globals"
                       "-repr-procedure" "class"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "/usr/local/bin/ruby") ;; ruby 1.9.3p392
    ("ruby"   ".rb"   ("-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "class"
                      )
                      "/usr/local/bin/ruby") ;; ruby 1.9.3p392
    ("ruby"   ".rb"   ("-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "host"
                      )
                      "/usr/local/bin/ruby") ;; ruby 1.9.3p392
|#
#;
    ("php"   ".php"   ()
                      "/usr/bin/php") ;; PHP 5.5.20

    ;; repr-module = globals
    ("php"    ".php"  ("-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "/usr/bin/php") ;; PHP 5.5.20
    ("php"    ".php"  ("-repr-module"    "globals"
                       "-repr-procedure" "class"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "/usr/bin/php") ;; PHP 5.5.20
    ("php"    ".php"  ("-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "class"
                      )
                      "/usr/bin/php") ;; PHP 5.5.20
    ("php"    ".php"  ("-repr-module"    "globals"
                       "-repr-procedure" "host"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "host"
                      )
                      "/usr/bin/php") ;; PHP 5.5.20

    ;; repr-module = globals
    ("php"    ".php"  ("-pre53"
                       "-repr-module"    "globals"
                       "-repr-procedure" "class"
                       "-repr-fixnum"    "host"
                       "-repr-flonum"    "class"
                      )
                      "/Users/feeley/php5.2.17/bin/php")
    ("php"    ".php"  ("-pre53"
                       "-repr-module"    "globals"
                       "-repr-procedure" "class"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "class"
                      )
                      "/Users/feeley/php5.2.17/bin/php")
    ("php"    ".php"  ("-pre53"
                       "-repr-module"    "globals"
                       "-repr-procedure" "class"
                       "-repr-fixnum"    "class"
                       "-repr-flonum"    "host"
                      )
                      "/Users/feeley/php5.2.17/bin/php")

#;
    ("dart"   ".dart" ()
                      "/Users/feeley/dart/dart-sdk/bin/dart")
   ))

(define (find-files file-or-dir filter)
  (if (eq? (file-type file-or-dir) 'directory)

      (apply
       append
       (map
        (lambda (f)
          (find-files (path-expand f file-or-dir) filter))
        (directory-files file-or-dir)))

      (if (filter file-or-dir)
          (list file-or-dir)
          (list))))

(define (list-of-scm-files args stress?)
  (apply
   append
   (map
    (lambda (f)
      (find-files f
                  (lambda (filename)
                    (and (equal? (path-extension filename) ".scm")
                         (not (equal? (path-strip-directory filename) "#.scm"))
                         (or stress?
                             (let ((len (string-length filename)))
                               (not (and (> len 11)
                                         (equal? (substring filename (- len 11) len)
                                                 "-stress.scm")))))))))
    args)))

(define (keep keep? lst)
  (cond ((null? lst)       '())
        ((keep? (car lst)) (cons (car lst) (keep keep? (cdr lst))))
        (else              (keep keep? (cdr lst)))))

(define modes '())
(define targets '())

(define default-dir
  (let* ((cd (current-directory))
         (len (string-length cd)))
    (string-append "tests" (substring cd (- len 1) len))))

(define (main . args)

  (define stress? #f)

  (current-exception-handler
   (lambda (e)
     (current-exception-handler (lambda (e) (##exit 1)))
     (display-exception e)
     (if (scheduler-exception? e)
         (begin
           (write e)
           (display " = ")
           (display-exception (##vector-ref e 1))))
     (##exit 1)))

  (let loop ()
    (if (and (pair? args)
             (> (string-length (car args)) 1)
             (char=? #\- (string-ref (car args) 0)))
        (let ((word (substring (car args) 1 (string-length (car args)))))
          (cond ((equal? word "stress")
                 (set! stress? #t))
                ((member word '("C" "js" "python" "ruby" "php" "java"))
                 (set! targets
                       (cons (string->symbol word)
                             targets)))
                (else
                 (set! modes
                       (cons (string->symbol word)
                             modes))))
          (set! args (cdr args))
          (loop))))

  (if (null? args)
      (set! args (list default-dir)))

  (if (null? modes)
      (set! modes '(gsi)))

  (if (null? targets)
      (set! targets '(C)))

  (let ((files
         (sort-list
          (list-of-scm-files args stress?)
          string<?)))
    (run-tests files)))

;;;============================================================================

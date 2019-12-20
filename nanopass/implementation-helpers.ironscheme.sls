;;; Copyright (c) 2000-2018 Dipanwita Sarkar, Andrew W. Keep, R. Kent Dybvig, Oscar Waddell
;;; See the accompanying file Copyright for details

(library (nanopass implementation-helpers)
  (export
    ;; formatting
    format printf pretty-print
    
    ;; listy stuff
    iota make-list list-head

    ;; gensym stuff (related to nongenerative languages)
    gensym regensym

    ;; source-information stuff
    syntax->source-information
    source-information-source-file
    source-information-byte-offset-start
    source-information-char-offset-start
    source-information-byte-offset-end
    source-information-char-offset-end
    source-information-position-line
    source-information-position-column
    source-information-type
    provide-full-source-information

    ;; library export stuff (needed for when used inside module to
    ;; auto-indirect export things)
    indirect-export

    ;; compile-time environment helpers
    define-property make-compile-time-value

    ;; code organization helpers
    module

    ;; useful for warning and error items
    warningf errorf

    ;; used to get the best performance from hashtables
    eq-hashtable-set! eq-hashtable-ref

    ;; debugging support
    trace-lambda trace-define-syntax trace-let trace-define
    
    ;; needed to know what code to generate
    optimize-level

    ;; the base record, so that we can use gensym syntax
    define-nanopass-record

    ;; failure token so that we can know when parsing fails with a gensym
    np-parse-fail-token

    ;; handy syntactic stuff
    with-implicit

    ;; abstraction of the grabbing the syntactic environment that will work in
    ;; Chez, Ikarus, Vicare and IronScheme
    with-compile-time-environment

    ;; apparently not neeaded (or no longer needed)
    ; scheme-version= scheme-version< scheme-version> scheme-version>=
    ; scheme-version<= with-scheme-version gensym? errorf with-output-to-string
    ; with-input-from-string
    )
  (import 
    (rnrs) 
    (rnrs eval) 
    (ironscheme) 
    (nanopass syntactic-property)
    (ironscheme core)
    (ironscheme clr)
    (ironscheme reader))

  (define optimize-level (make-parameter 0)) ;; not sure what this is used for (yet)

  (define-syntax with-implicit
    (syntax-rules ()
      [(_ (id name ...) body bodies ...)
       (with-syntax ([name (datum->syntax #'id 'name)] ...) body bodies ...)]))

  ; the base language
  (define-syntax define-nanopass-record
    (lambda (x)
      (syntax-case x ()
        [(k) (with-implicit (k nanopass-record nanopass-record? nanopass-record-tag)
               #'(define-record-type (nanopass-record make-nanopass-record nanopass-record?)
                   (nongenerative nanopass-record-d47f8omgluol6otrw1yvu5-0)
                   (fields (immutable tag nanopass-record-tag))))])))
 
  ;; another gensym listed into this library
  ;; what is this used for?
  (define np-parse-fail-token 'np-parse-fail-token-dlkcd4b37swscag1dvmuiz-13)

  (define-syntax eq-hashtable-set! (identifier-syntax hashtable-set!))
  (define-syntax eq-hashtable-ref (identifier-syntax hashtable-ref))

  (define list-head
    (lambda (orig-ls orig-n)
      (let f ([ls orig-ls] [n orig-n])
        (cond
          [(fxzero? n) '()]
          [(null? ls) (error 'list-head "index out of range" orig-ls orig-n)]
          [else (cons (car ls) (f (cdr ls) (fx- n 1)))]))))

  (define iota
    (lambda (n)
      (let loop ([n n] [ls '()])
        (if (fxzero? n)
            ls
            (let ([n (fx- n 1)])
              (loop n (cons n ls)))))))

  (define (gensym? s) (eq? s (ungensym s)))              

  ;; just stuffing info for now... I guess it is needed for prettiness only?
  (define regensym
    (case-lambda
      [(gs extra)
       (unless (gensym? gs) (errorf 'regensym "~s is not a gensym" gs))
       (unless (string? extra) (errorf 'regensym "~s is not a string" extra))
      ;  (let ([pretty-name (parameterize ([print-gensym #f]) (format "~s" gs))]
      ;        [unique-name (gensym->unique-string gs)])
      ;    (with-input-from-string (format "~a-~a~a" pretty-name unique-name extra) read))
       (gensym (format "~a~a" gs extra))]
      [(gs extra0 extra1)
       (unless (gensym? gs) (errorf 'regensym "~s is not a gensym" gs))
       (unless (string? extra0) (errorf 'regensym "~s is not a string" extra0))
       (unless (string? extra1) (errorf 'regensym "~s is not a string" extra1))
      ; (with-output-to-string (lambda () (format "~s" gs)))
      ;  (let ([pretty-name (parameterize ([print-gensym #f]) (format "~s" gs))]
      ;        [unique-name (gensym->unique-string gs)])
      ;    (with-input-from-string (format "~a~a-~a~a" pretty-name extra0 unique-name extra1) read))
       (gensym (format "~a~a~a" gs extra0 extra1))
      ]))

  (define provide-full-source-information
    (make-parameter #f (lambda (x) (and x #t))))

  (define-record-type source-information
    (nongenerative)
    (sealed #t)
    (fields source-file byte-offset-start char-offset-start byte-offset-end
      char-offset-end position-line position-column type)
    (protocol
      (lambda (new)
        (lambda (a type)
          (let* ([as (annotation-source a)][cp (car (clr-static-call IronScheme.Runtime.Builtins SourceLocation (cdr as)))])
            (let ([fn (car as)] [line (car cp)][col (cdr cp)])
              ;; the line/col info from the reader is pretty accurate, do I need the stuff below?
              (if (provide-full-source-information)
                  (call-with-input-file fn
                    (lambda (ip)
                      (let loop ([n cp] [line 1] [col 0])
                        (if (= n 0)
                            (new fn (port-position ip) cp #f #f line col type)
                            (let ([c (read-char ip)])
                              (if (char=? c #\newline)
                                  (loop (- n 1) (fx+ line 1) 0)
                                  (loop (- n 1) line (fx+ col 1)))))))) 
                  (new fn #f #f #f #f line col type))))))))

  (define syntax->source-information
    (lambda (stx)
      (let loop ([stx stx] [type 'at])
        (cond
          [(stx? stx)
           (let ([e (stx-expr stx)])
             (and (annotation? e) (make-source-information e type)))]
          [(pair? stx) (or (loop (car stx) 'near) (loop (cdr stx) 'near))]
          [else #f]))))          

  (define-syntax errorf
    (syntax-rules ()
      [(_ who fmt args ...) (error who (format fmt args ...))]))
 
  (define-syntax warningf
    (syntax-rules ()
      [(_ who fmt args ...) (warning who (format fmt args ...))]))

  (define-syntax indirect-export
    (syntax-rules ()
      [(_ id indirect-id ...) (define t (if #f #f))]))

  (define-syntax define-property
    (lambda (x)
      (syntax-case x ()
        [(_ id key value)
         (with-syntax ([t (datum->syntax #'id (gensym (syntax->datum #'id)))])
           (syntax-property-set! #'id #'key (syntax->datum #'t))
           #'(define-syntax waste (let () (set-symbol-value! 't value) (lambda (x) (syntax-violation #f "invalid syntax" x)))))])))

  (define-syntax with-compile-time-environment
    (syntax-rules ()
      [(k (arg) body* ... body)
       (lambda (rho)
         (let ([arg (case-lambda
                      [(x) (rho x)]
                      [(x y) (let ([sym (syntax-property-get x y #f)])
                               (and sym (symbol-value sym)))])])
           body* ... body))])))

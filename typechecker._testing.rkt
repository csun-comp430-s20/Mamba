#lang racket
;TYPE CHECKER TEST FILE
(require rackunit)
(require "parser.rkt")

(struct Int_Type ([hash_code #:auto])
  #:auto-value 0)
(provide (struct-out Int_Type))
(struct String_Type ([hash_code #:auto])
  #:auto-value 1)
(provide (struct-out String_Type))
(struct Bool_Type ([hash_code #:auto])
  #:auto-value 2)
(provide (struct-out Bool_Type))

(struct Enum_Type ([hash_code #:auto])
  #:auto-value 3)
(provide (struct-out Enum_Type))

(define (type_of gamma exp)
  (cond
    [(Integer_Expression? exp) (Int_Type)]
    [(String_Expression? exp) (String_Type)]
    [(Boolean_Expression? exp) (Bool_Type)]
    [(Variable_Expression? exp) (if (hash-has-key? gamma (Variable_Expression-value exp)) (hash-ref gamma (Variable_Expression-value exp)) (error "Variable " (Variable_Expression-value exp) " is out of scope."))]
    [(Additive_Expression? exp) (if (and (Int_Type? (type_of gamma (ParseResult-result (Additive_Expression-primary1 exp)))) (Int_Type? (type_of gamma (ParseResult-result (Additive_Expression-primary2 exp))))) (Int_Type) (error "one or more expressions is not an int in an additive expression"))]
    [(Multiplicative_Expression? exp) (if (and (Int_Type? (type_of gamma (ParseResult-result (Multiplicative_Expression-primary1 exp)))) (Int_Type? (type_of gamma (ParseResult-result (Multiplicative_Expression-primary2 exp))))) (Int_Type) (error "one or more expressions is not an int in a multiplicative expression"))]
    [(Boolean_Operation_Expression? exp)
     (let ([exp1 (type_of gamma (ParseResult-result (Boolean_Operation_Expression-primary1 exp)))] [exp2 (type_of gamma (ParseResult-result (Boolean_Operation_Expression-primary2 exp)))])
       (cond
         [(and (Bool_Type? exp1) (Bool_Type? exp2)) (Bool_Type)]
         [(and (Int_Type? exp1) (Int_Type? exp2)) (Bool_Type)]
         [else (error "one or more expressions is not a boolean in a boolean operation")]))]
    [(If_Expression? exp)
     (let ([gaurd (type_of gamma (ParseResult-result (If_Expression-gaurd exp)))] [ifTrue (ParseResult-result (If_Expression-ifTrue exp))] [ifFalse (ParseResult-result (If_Expression-ifFalse exp))])
       (if (Bool_Type? gaurd) (check_ifTrue_and_ifFalse gamma ifTrue ifFalse gaurd) (error "gaurd for if expression is type: " gaurd ". Expected type boolean")))]
    [(Assignment_Statement? exp)
     (let ([tau (determine_type_of (ParseResult-result (Assignment_Statement-type exp)))] [name (ParseResult-result (Assignment_Statement-identifier exp))] [e (type_of gamma (ParseResult-result (Assignment_Statement-exp exp)))])
       (if (hash-has-key? gamma name)
           (error "variable " name " has already been declared.")
           (if (equal? (object-name tau) (object-name e))
               (update_gamma_and_return_tau gamma name tau)
               (if (equal? (object-name tau) (object-name (first e)))
                   (update_gamma_higher_order_and_return_tau gamma name e)
                   (error "Type " tau " cannot be converted to " e)))))]
    [(While_Statement? exp)
     (let ([gaurd (type_of gamma (ParseResult-result (While_Statement-gaurd exp)))] [body (ParseResult-result (While_Statement-body exp))])
       (if (Bool_Type? gaurd)
           (let ([copy (hash-copy gamma)])
             (for-each (lambda (arg)
                         (type_of copy arg))
               body))
           (error "While statement expected a gaurd of type boolean but was given a gaurd of type: " gaurd)))]
    [(Function_Expression? exp)
     (let ([type (determine_type_of (ParseResult-result (Function_Expression-type exp)))] [name (ParseResult-result (Function_Expression-identifier exp))])
       (if (not (hash-has-key? gamma name)) (type_check_function gamma type name (ParseResult-result (Function_Expression-parameters exp)) (ParseResult-result (Function_Expression-body exp)) (ParseResult-result (Function_Expression-returned exp))) (error name " has already been defined")))]
    [(Call_Expression? exp) (type_check_call_expression gamma (ParseResult-result (Call_Expression-identifier exp)) (ParseResult-result (Call_Expression-arguments exp)))]
    [(Print_Statement? exp) (type_of gamma (ParseResult-result (Print_Statement-exp exp)))]
    [(Enum_Statement? exp) (type_check_enum_statement gamma (Variable_Expression-value (ParseResult-result (Enum_Statement-identifier exp))) (ParseResult-result (Enum_Statement-cases exp)))]
    [(Switch_Statement? exp) (type_check_switch_statement gamma (ParseResult-result (Switch_Statement-exp exp)) (ParseResult-result (Switch_Statement-cases exp)) (ParseResult-result (Switch_Statement-default exp)))]
    [(Enum_Reference_Statement? exp) (type_check_enum_reference gamma (Enum_Reference_Statement-enum_name exp) (Enum_Reference_Statement-enum_case exp))]
    [(ParseResult? exp) (type_of gamma (ParseResult-result exp))]
    [else (error "unrecognized expression") null]))


(define (type_check_enum_reference gamma enum_name enum_case)
  (if (hash-has-key? gamma (string-append enum_name (string-append "." enum_case)))
      (hash-ref gamma (string-append enum_name (string-append "." enum_case)))
      (error "enum case, " enum_case ", has not been declared.")))

(define (type_check_enum_statement gamma name cases)
  (if (hash-has-key? gamma name)
      (error "identifier " name " has already been declared.")
      (for-each (lambda (arg)
                  (hash-set! gamma (string-append name (string-append "." arg)) (Enum_Type)))
                (type_check_enum_cases gamma cases (list))))
  (hash-set! gamma name (Enum_Type))
  (hash-ref gamma name))


(define (type_check_enum_cases gamma cases collection)
  (if (null? cases)
      collection
      (if (and (not (hash-has-key? gamma (Variable_Expression-value (ParseResult-result (first cases))))) (not (member (Variable_Expression-value (ParseResult-result (first cases))) collection)))
          (type_check_enum_cases gamma (rest cases) (append collection (list (Variable_Expression-value (ParseResult-result (first cases))))))
          (error "identifier " (Variable_Expression-value (ParseResult-result (first cases))) " has already been declared."))))

(define (type_check_switch_statement gamma exp cases default)
  (type_of (hash-copy gamma) default)
  (let ([exp_type (type_of gamma exp)])
    (if (equal? exp_type (type_check_switch_case (hash-copy gamma) exp_type cases))
        exp_type
        (error "type of case does not match type of: " exp_type))))

(define (type_check_switch_case copy exp_type cases)
  (if (null? cases)
      exp_type
      (if (equal? (object-name exp_type) (object-name (type_of copy (first (first cases)))))
          (type_check_a_switch_case_body copy exp_type (rest cases) (ParseResult-result (second (first cases))))
          (error "switch case does not have type: " exp_type))))

(define (type_check_a_switch_case_body copy exp_type cases a_case_body)
  (type_of copy a_case_body)
  (type_check_switch_case copy exp_type cases))

(define (update_gamma_higher_order_and_return_tau gamma name e)
  (hash-set! gamma name e)
  (first e))

(define (type_check_call_expression gamma name args)
  (if (hash-has-key? gamma name)
      (if (compare_arg_types_with_param_types  (second (hash-ref gamma name)) (collect_arg_types gamma (list) args) #false)
          (first (hash-ref gamma name))
          (error "arguments do not match parameters"))
  (error name " has not been declared")))

(define (collect_arg_types gamma types args)
  (if (not (null? args))
      (collect_arg_types gamma (append types (list (type_of gamma (ParseResult-result (first (first args)))))) (rest args))
      types))

(define (compare_arg_types_with_param_types param_types arg_types check)
  (if (and (equal? (length param_types) (length arg_types)) (and (not (null? param_types)) (not (null? arg_types))))
      (if (equal? (object-name (first param_types)) (object-name (first arg_types)))
          (compare_arg_types_with_param_types (rest param_types) (rest arg_types) #true)
          (error "arguments do not match parameter types"))
      check))

(define (type_check_function gamma type name parameters body returned)
  (let ([copy (hash-copy gamma)])
    (update_gamma_with_function_parameters copy parameters)
    (for-each (lambda (arg)
              (type_of copy (ParseResult-result arg)))
              body)
    (let ([tau2 (type_of copy returned)])
      (if (equal? (object-name type) (object-name (unpack_list tau2))) (add_function_to_gamma gamma name tau2 (collect_function_parameters_types (list) parameters (list))) (error "expected a return type of " type)))))

(define (unpack_list list)
  (if (list? list)
      (unpack_list (first list))
      list))

(define (add_function_to_gamma gamma name type params)
  (hash-set! gamma name (list type params))
  type)

(define (update_gamma_function_append_symbol_table gamma name tau1 tau2)
  (hash-set! gamma name (append tau1 (list tau2)))
  tau2)

(define (collect_function_parameters_types param_types parameters param_names_holder)
  (if (not (null? parameters))
      (let ([a_param (ParseResult-result (first (first parameters)))])
        (if (not (member a_param param_names_holder))
            (collect_function_parameters_types (append param_types (list (determine_type_of a_param))) (rest parameters) (append param_names_holder (list a_param)))
            (error "duplicate parameter")))
      param_types))


(define (update_gamma_with_function_parameters copy parameters)
  (if (not (null? parameters))
      (update_gamma_with_function_parameters (hash-set! copy (Variable_Expression-value (ParseResult-result (second (first parameters)))) (determine_type_of (ParseResult-result (first (first parameters))))) (rest parameters))
      copy))

(define (check_ifTrue_and_ifFalse gamma ifTrue ifFalse gaurd)
  (type_of (hash-copy gamma) ifTrue)
  (type_of (hash-copy gamma) ifFalse)
  gaurd)

(define (update_gamma_and_return_tau gamma name tau) (hash-set! gamma name tau) tau)

(define (determine_type_of tau)
  (cond
    [(equal? tau "int") (Int_Type)]
    [(equal? tau "String") (String_Type)]
    [(equal? tau "boolean") (Bool_Type)]
    [else (error "unrecognized type: " tau)]))
 
(define (top_level_check ast_list gamma)
  (if (not (null? ast_list))
      (if (not (null? (type_of gamma (ParseResult-result (first ast_list)))))
          (top_level_check (rest ast_list) gamma)
          (error "unable to type check program"))
      gamma))


;Part 1
;Format: (check equal? (object-name ({function to be tested} {parameters for that function})) (object-name ({Type expected})))

(check equal? (object-name (type_of (make-hash) (Integer_Expression "1"))) (object-name (Int_Type)))

(check equal? (object-name (type_of (make-hash) (String_Expression "test"))) (object-name (String_Type)))

;Part 2
;When running this file, in the console, it will ask you to input a file to compile. Just put test.txt because this part will have no effect on running this file
;If nothing happens then it worked











;;; -*- Mode: Lisp; Package: ESA-UTILS -*-

;;;  (c) copyright 2006 by
;;;           Troels Henriksen (athas@sigkill.dk)

;;; This library is free software; you can redistribute it and/or
;;; modify it under the terms of the GNU Library General Public
;;; License as published by the Free Software Foundation; either
;;; version 2 of the License, or (at your option) any later version.
;;;
;;; This library is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Library General Public License for more details.
;;;
;;; You should have received a copy of the GNU Library General Public
;;; License along with this library; if not, write to the
;;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;;; Boston, MA  02111-1307  USA.

;;; Miscellaneous utilities used in ESA.

(in-package :esa-utils)

;;; Cribbed from Paul Graham
(defmacro with-gensyms (syms &body body)
  `(let ,(mapcar #'(lambda (s) `(,s (gensym))) syms)
     ,@body))

;;; Cribbed from PCL by Seibel
(defmacro once-only ((&rest names) &body body)
  (let ((gensyms (loop for n in names collect (gensym))))
    `(let (,@(loop for g in gensyms collect `(,g (gensym))))
       `(let (,,@(loop for g in gensyms for n in names collect ``(,,g ,,n)))
          ,(let (,@(loop for n in names for g in gensyms collect `(,n ,g)))
                ,@body)))))

(defun unlisted (obj &optional (fn #'first))
  (if (listp obj)
      (funcall fn obj)
      obj))

(defun fully-unlisted (obj &optional (fn #'first))
  (if (listp obj)
      (fully-unlisted (funcall fn obj))
      obj))

(defun listed (obj)
  (if (listp obj)
      obj
      (list obj)))

(defun list-aref (list &rest subscripts)
  (if subscripts
      (apply #'list-aref (nth (first subscripts) list)
             (rest subscripts))
      list))

;;; Cribbed from McCLIM.
(defun check-letf-form (form)
  (assert (and (listp form)
               (= 2 (length form)))))

(defun valueify (list)
  (if (and (consp list)
           (endp (rest list)))
      (first list)
      `(values ,@list)))

(defmacro letf ((&rest forms) &body body &environment env)
  "LETF ({(Place Value)}*) Declaration* Form* During evaluation of the
Forms, SETF the Places to the result of evaluating the Value forms.
The places are SETF-ed in parallel after all of the Values are
evaluated."
  (mapc #'check-letf-form forms)
  (let* (init-let-form save-old-values-setf-form
         new-values-set-form old-values-set-form
         update-form)
    (loop for (place new-value) in forms
       for (vars vals store-vars writer-form reader-form)
         = (multiple-value-list (get-setf-expansion place env))
       for old-value-names = (mapcar (lambda (var)
                                       (declare (ignore var))
                                       (gensym))
                                     store-vars)
       nconc (mapcar #'list vars vals) into temp-init-let-form
       nconc (copy-list store-vars) into temp-init-let-form
       nconc (copy-list old-value-names) into temp-init-let-form
       nconc `(,(valueify old-value-names) ,reader-form) into temp-save-old-values-setf-form
       nconc `(,(valueify store-vars) ,new-value) into temp-new-values-set-form
       nconc `(,(valueify store-vars) ,(valueify old-value-names)) into temp-old-values-set-form
       collect writer-form into temp-update-form
       finally (setq init-let-form temp-init-let-form
                     save-old-values-setf-form temp-save-old-values-setf-form
                     new-values-set-form temp-new-values-set-form
                     old-values-set-form temp-old-values-set-form
                     update-form (cons 'progn temp-update-form)))
    `(let* ,init-let-form
       (setf ,@save-old-values-setf-form)
       (unwind-protect
            (progn (setf ,@new-values-set-form)
                   ,update-form
                   (progn ,@body))
         (setf ,@old-values-set-form)
         ,update-form))))

(defun invoke-with-dynamic-bindings-1 (bindings continuation)
  (let ((old-values (mapcar #'(lambda (elt)
                                (symbol-value (first elt)))
                            bindings)))
    (unwind-protect (progn
                      (mapcar #'(lambda (elt)
                                  (setf (symbol-value (first elt))
                                        (funcall (second elt))))
                              bindings)
                      (funcall continuation))
      (mapcar #'(lambda (elt value)
                  (setf (symbol-value (first elt))
                        value))
              bindings old-values))))

(defmacro invoke-with-dynamic-bindings ((&rest bindings) &body body)
  `(invoke-with-dynamic-bindings-1
    ,(loop for (symbol expression) in bindings
        collect (list `',symbol
                      `#'(lambda ()
                           ,expression)))
    #'(lambda ()
        ,@body)))

;;; XXX This is currently broken with respect to declarations

(defmacro letf* ((&rest forms) &body body)
  (if (null forms)
      `(locally
	 ,@body)
      `(letf (,(car forms))
	 (letf* (,(cdr forms))
	   ,@body))))

(defun display-string (string)
  (with-output-to-string (result)
    (loop for char across string
	  do (cond ((graphic-char-p char) (princ char result))
		((char= char #\Space) (princ char result))
		(t (prin1 char result))))))

(defun object-equal (x y)
  "Case insensitive equality that doesn't require characters"
  (if (characterp x)
      (and (characterp y) (char-equal x y))
      (eql x y)))

(defun object= (x y)
  "Case sensitive equality that doesn't require characters"
  (if (characterp x)
      (and (characterp y) (char= x y))
      (eql x y)))

(defun no-upper-p (string)
  "Does STRING contain no uppercase characters"
  (notany #'upper-case-p string))

(defun case-relevant-test (string)
  "Returns a test function based on the search-string STRING.
If STRING contains no uppercase characters the test is case-insensitive,
otherwise it is case-sensitive."
  (if (no-upper-p string)
      #'object-equal
      #'object=))

(defun remove-keywords (arg-list keywords)
  (let ((clean-tail arg-list))
    ;; First, determine a tail in which there are no keywords to be removed.
    (loop for arg-tail on arg-list by #'cddr
	  for (key) = arg-tail
	  do (when (member key keywords :test #'eq)
	       (setq clean-tail (cddr arg-tail))))
    ;; Cons up the new arg list until we hit the clean-tail, then nconc that on
    ;; the end.
    (loop for arg-tail on arg-list by #'cddr
	  for (key value) = arg-tail
	  if (eq arg-tail clean-tail)
	    nconc clean-tail
	    and do (loop-finish)
	  else if (not (member key keywords :test #'eq))
	    nconc (list key value)
	  end)))

(defmacro with-keywords-removed ((var keywords &optional (new-var var))
				 &body body)
  "binds NEW-VAR (defaults to VAR) to VAR with the keyword arguments specified
in KEYWORDS removed."
  `(let ((,new-var (remove-keywords ,var ',keywords)))
     ,@body))

(defun maptree (fn x)
  "This auxiliary function is like MAPCAR but has two extra
purposes: (1) it handles dotted lists; (2) it tries to make the
result share with the argument x as much as possible."
  (if (atom x) 
      (funcall fn x) 
      (let ((a (funcall fn (car x))) 
            (d (maptree fn (cdr x)))) 
        (if (and (eql a (car x)) (eql d (cdr x))) 
            x 
            (cons a d)))))

(defun subtype-compatible-p (types)
  "Return true if an element of `types' is a subtype of every
other type specifier in `types'. `Types' must be a list of type
specifiers."
  (some (lambda (x)
          (subtypep x `(and ,@types))) types))

(defun capitalize (string)
  "Return `string' with the first character
capitalized (destructively modified)."
  (setf (elt string 0) (char-upcase (elt string 0)))
  string)

(defun ensure-array-size (array min-size new-elem-fn)
  "Ensure that `array' is at least of size `min-size'. If `array'
needs to be resized, call `new-elem-fn' with no arguments to
generate the elements of the new cells in the array. Returns
`array'. Currently, this function only works when `array' is a
vector."
  (when (< (length array) min-size)
    (let ((old-length (length array)))
      (setf array (adjust-array array
                                (max (* old-length 2) min-size)))
      (loop for i from old-length below (length array)
         do (setf (elt array i) (funcall new-elem-fn)))))
  array)

(define-method-combination values-max-min
    (&optional (order ':most-specific-last))
  ((around (:around))
   (before (:before))
   (after (:after))
   (primary (values-max-min) :order order :required t))
  (flet ((call-methods (methods)
	   (mapcar (lambda (m) `(call-method ,m)) methods))
	 (call-vmm-methods (methods)
	   `(multiple-value-bind (max min)
	        (call-method ,(first methods))
              (progn
                ,@(loop for m in (rest methods)
                     collect `(multiple-value-bind (mmax mmin)
                                  (call-method ,m)
                                (setq max (max max mmax)
                                      min (min min mmin)))))
              (values max min))))
    (let ((form (if (or around before after (rest primary))
		    `(multiple-value-prog1 
                         (progn ,@(call-methods before)
                                ,(call-vmm-methods primary))
                       (progn ,@(call-methods (reverse after))))
		    `(call-method ,(first primary)))))
      (if around
	  `(call-method ,(first around) (,@(rest around) (make-method ,form)))
	  form))))

(defclass observable-mixin ()
  ((%observers :accessor observers
               :initform '()))
  (:documentation "A mixin class that adds the capability for a
subclass to have a list of \"event subscribers\" (observers) that
can be informed via callback (the function `observer-notified')
whenever the state of the object changes. The order in which
observers will be notified is undefined."))

(defgeneric add-observer (observable observer)
  (:documentation "Add an observer to an observable object. If
the observer is already observing `observable', it will not be
added again."))

(defmethod add-observer ((observable observable-mixin) observer)
  ;; Linear in complexity, perhaps a transparent switch to a hash
  ;; table would be a good idea for large amounts of observers.
  (pushnew observer (observers observable)))

(defgeneric remove-observer (observable observer)
  (:documentation "Remove an observer from an observable
object. If observer is not in the list of observers of
`observable', nothing will happen."))

(defmethod remove-observer ((observable observable-mixin) observer)
  (setf (observers observable)
        (delete observer (observers observable))))

(defgeneric observer-notified (observer observable data)
  (:documentation "This function is called by `observable' when
its state changes on each observer that is observing
it. `Observer' is the observing object, `observable' is the
observed object. `Data' is arbitrary data that might be of
interest to `observer', it is recommended that subclasses of
`observable-mixin' specify exactly which form this data will
take, the observer protocol does not guarantee anything. It is
non-&optional so that methods may be specialised on it, if
applicable. The default method on this function is a no-op, so it
is never an error to not define a method on this generic function
for an observer.")
  (:method (observer (observable observable-mixin) data)
    ;; Never a no-applicable-method error.
    nil))

(defgeneric notify-observers (observable &optional data-fn)
  (:documentation "Notify each observer of `observable' by
calling `observer-notified' on them. `Data-fn' will be called,
with the observer as the single argument, to obtain the `data'
argument to `observer-notified'. The default value of `data-fn'
should cause the `data' argument to be NIL."))

(defmethod notify-observers ((observable observable-mixin)
                             &optional (data-fn (constantly nil)))
  (dolist (observer (observers observable))
    (observer-notified observer observable
                       (funcall data-fn observer))))

(defclass name-mixin ()
  ((%name :accessor name
          :initarg :name
          :type string
          :documentation "The name of the named object."))
  (:documentation "A class used for defining named objects."))

(defclass subscriptable-name-mixin (name-mixin)
  ((%subscript :accessor subscript
               :documentation "The subscript of the named object.")
   (%subscript-generator :accessor subscript-generator
                         :initarg :subscript-generator
                         :initform (constantly 1)
                         :documentation "A function used for
finding the subscript of a `name-mixin' whenever the name is
set (including during object initialization). This function will
be called with the name as the single argument."))
  (:documentation "A class used for defining named objects. A
facility is provided for assigning a named object a \"subscript\"
uniquely identifying the object if there are other objects of the
same name in its collection (in particular, if an editor has two
buffers with the same name)."))

(defmethod initialize-instance :after ((name-mixin subscriptable-name-mixin)
                                       &rest initargs)
  (declare (ignore initargs))
  (setf (subscript name-mixin)
        (funcall (subscript-generator name-mixin) (name name-mixin))))

(defmethod subscripted-name ((name-mixin subscriptable-name-mixin))
  ;; Perhaps this could be written as a single format statement?
  (if (/= (subscript name-mixin) 1)
      (format nil "~A <~D>" (name name-mixin) (subscript name-mixin))
      (name name-mixin)))

(defmethod (setf name) :after (new-name (name-mixin subscriptable-name-mixin))
  (setf (subscript name-mixin)
        (funcall (subscript-generator name-mixin) new-name)))

;;; "Modes" are a generally useful concept, so let's define some
;;; primitives for them here.

(defclass mode ()
  ()
  (:documentation "A superclass for all modes."))

(defclass modual-mixin ()
  ((%original-class-name :accessor original-class-name
                         :documentation "The original name of the
class the `modual-mixin' is part of, the actual name will change
as modes are added and removed."))
  (:documentation "A mixin for objects supporting modes."))

(defmethod initialize-instance :after ((object modual-mixin) &rest initargs)
  (declare (ignore initargs))
  (setf (original-class-name object) (class-name (class-of object))))

(defgeneric available-modes (modual)
  (:documentation "Return all available modes for `modual'. Not
all of the modes may be applicable, use the `applicable-modes'
function if you're only interested in these.")
  (:method-combination append)
  (:method append ((modual modual-mixin))
    '()))

(defgeneric mode-directly-applicable-p (modual mode-name)
  (:documentation "Return true if the mode of the name
`mode-name' can be directly enabled for `modual'. If the mode of
name `mode-name' is unapplicable, an error of type
`nonapplicable-mode' will be signalled. This allows a sort of
\"opt-out\" where a mode can forcefully prevent another specific
mode from being enabled. ")
  (:method-combination or)
  (:method or ((modual modual-mixin) mode-name)
     nil))

(defgeneric mode-applicable-p (modual mode-name)
  (:documentation "Return true if the mode of the name
`mode-name' can be enabled for `modual' or some sub-object of
`modual'. If the mode of name `mode-name' is unapplicable, an
error of type `nonapplicable-mode' will be signalled. This allows
a sort of \"opt-out\" where a mode can forcefully prevent another
specific mode from being enabled. ")
  (:method-combination or)
  (:method or ((modual modual-mixin) mode-name)
     (mode-directly-applicable-p modual mode-name)))

(defgeneric enabled-modes (modual)
  (:documentation "Return a list of the names of the modes
directly enabled for `modual'.")
  (:method-combination append)
  (:method append ((modual modual-mixin))
     '()))

(defgeneric mode-enabled-p (modual mode-name)
  (:documentation "Return true if `mode-name' is enabled for
`modual' or any modual \"sub-objects\"." )
  (:method-combination or)
  (:method or ((modual modual-mixin) mode-name)
     (member mode-name (enabled-modes modual) :test #'equal)))

(define-condition nonapplicable-mode (error)
  ((%modual :accessor modual
            :initarg :modual
            :initform (error "The modual used in the error-causing operation must be supplied")
            :documentation "The modual that the mode is attempted to be enabled for")
   (%mode-name :accessor mode-name
               :initarg :mode-name
               :initform (error "The name of the problematic mode must be supplied")
               :documentation "The name of the mode that cannot be enabled for the view"))
  (:documentation "This error is signalled if a mode is attempted
enabled for a modual that the mode is not applicable to.")
  (:report (lambda (condition stream)
             (format
              stream "The mode ~A is not applicable for ~A"
              (mode-name condition) (modual condition)))))

(defun nonapplicable-mode (modual mode-name)
  "Signal an error of type `nonapplicable-mode' with `modual' and
`mode-name' as arguments."
  (error 'nonapplicable-mode :modual modual :mode-name mode-name))

(defgeneric enable-mode (modual mode-name &rest initargs)
  (:documentation "Enable the mode of the name `mode-name' for
`modual', using `initargs' as options for the mode. If the mode
is already enabled, do nothing. If the mode is not applicable to
`modual', signal an `nonapplicable-mode' error.")
  (:method :around ((modual modual-mixin) mode-name &rest initargs)
     (declare (ignore initargs))
     (unless (mode-enabled-p modual mode-name)
       (call-next-method))))

(defgeneric disable-mode (modual mode-name)
  (:documentation "Disable the mode of the name `mode-name' for
`modual'. If a mode of the provided name is not enabled, do
nothing.")
  (:method :around ((modual modual-mixin) mode-name)
     (when (mode-enabled-p modual mode-name)
       (call-next-method))))

;;; In a perfect world, we would just combine `change-class' with
;;; anonymous classes to transparently add and remove mode classes
;;; (the "stealth mixin" concept). However, anonymous classes are the
;;; ugly child of CL, not well supported at all, so we'll have to do
;;; some ugly hacks involving the `eval'ing of constructed `defclass'
;;; forms, and caching the created classes to prevent memory leaking.

(defvar *class-cache* (make-hash-table :test #'equal)
  "A hash table mapping the name of a \"modual\" class to a
second hash table. This second hash table maps a list of mode
names to a class implementing this particular set of modes for
the modual class. Note that the order in which the modes appear
in the list is significant.")

(defun make-class-implementing-modes (modual modes)
  "Generate a class that is a subclass of `modual' that
implements all the modes listed as names in `modes'."
  ;; Avert thine eyes, thy of gentle spirit.
  (if (null modes)
      (find-class modual)
      (eval `(defclass ,(gensym) (,modual ,@modes) ()))))

(defun find-class-implementing-modes (modual modes)
  "Find, possibly create, the class implementing `modual' (a
class name) with `modes' (a list of mode names) as the enabled
modes."
  (let* ((modual-cache-hit (gethash modual *class-cache*))
         (modes-cache-hit (and modual-cache-hit
                               (gethash modes modual-cache-hit))))
    (or modes-cache-hit
        (setf (gethash modes
                       (or modual-cache-hit
                           (setf (gethash modual *class-cache*) 
                                 (make-hash-table :test #'equal))))
              (make-class-implementing-modes modual modes)))))

(defun change-class-for-enabled-mode (modual mode-name &rest initargs)
  "Change the class of `modual' so that it has a mode of name
`mode-name', created with the provided `initargs'."
  (apply #'change-class modual (find-class-implementing-modes
                                (original-class-name modual)
                                (cons mode-name (enabled-modes modual)))
         initargs))

(defun change-class-for-disabled-mode (modual mode-name)
  "Change the class of `modual' so that it does not have a mode
of name `mode-name'."
  (change-class modual (find-class-implementing-modes
                        (original-class-name modual)
                        (remove mode-name (enabled-modes modual)
                         :test #'equal))))

(defmethod enable-mode ((modual modual-mixin) mode-name &rest initargs)
  (if (mode-directly-applicable-p modual mode-name)
      (apply #'change-class-for-enabled-mode modual mode-name initargs)
      (nonapplicable-mode modual mode-name)))

(defmethod disable-mode ((modual modual-mixin) mode-name)
  (when (mode-directly-applicable-p modual mode-name)
    (change-class-for-disabled-mode modual mode-name)))

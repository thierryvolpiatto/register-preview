;;; register-preview.el --- Enhance register-preview -*- lexical-binding: t -*-

;; Author: Thierry Volpiatto <thievol@posteo.net>
;; Copyright (C) 2023 Thierry Volpiatto, all rights reserved.
;; URL: https://github.com/thierryvolpiatto/register-preview

;; Compatibility: GNU Emacs 25.1+"
;; Package-Requires: ((emacs "25.1"))
;; Version: 1.0

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.


;;; Commentary:
;;
;; Preview buffer is filtered according to register types.
;; Navigation available.
;; Default registers are proposed on creation.
;; Fully configurable with generics when new register commands are created.
;;
;; NOTE: `register-read-with-preview' is adviced in this package with
;; `register-preview--read-with-preview'.

;;; code:

(eval-when-compile (require 'cl-lib))
(require 'register)

(declare-function frameset-register-p "frameset")

(defgroup register-preview nil
  "Register preview for register commands."
  :group 'register)

(defcustom register-preview-default-keys (mapcar #'string (number-sequence ?a ?z))
  "The keys to use for setting a new register."
  :type '(repeat string))

(cl-defstruct register-preview-info
  "Store data for a specific register command.
TYPES are the types of register supported.
MSG is the minibuffer message to send when a register is selected.
ACT is the type of action the command is doing on register.
SMATCH accept a boolean value to say if command accept non matching register."
  types msg act smatch)

(cl-defgeneric register-preview-command-info (command)
  "Return a `register-preview-info' object storing data for COMMAND."
  (ignore command))
(cl-defmethod register-preview-command-info ((_command (eql insert-register)))
  (make-register-preview-info
   :types '(string number)
   :msg "Insert register `%s'"
   :act 'insert
   :smatch t))
(cl-defmethod register-preview-command-info ((_command (eql jump-to-register)))
  (make-register-preview-info
   :types  '(window frame marker kmacro
             file buffer file-query)
   :msg "Jump to register `%s'"
   :act 'jump
   :smatch t))
(cl-defmethod register-preview-command-info ((_command (eql view-register)))
  (make-register-preview-info
   :types '(all)
   :msg "View register `%s'"
   :act 'view
   :smatch t))
(cl-defmethod register-preview-command-info ((_command (eql append-to-register)))
  (make-register-preview-info
   :types '(string number)
   :msg "Append to register `%s'"
   :act 'modify
   :smatch t))
(cl-defmethod register-preview-command-info ((_command (eql prepend-to-register)))
  (make-register-preview-info
   :types '(string number)
   :msg "Prepend to register `%s'"
   :act 'modify
   :smatch t))
(cl-defmethod register-preview-command-info ((_command (eql increment-register)))
  (make-register-preview-info
   :types '(string number)
   :msg "Increment register `%s'"
   :act 'modify
   :smatch t))

(defun register-preview-forward-line (arg)
  "Move to next or previous line in register preview buffer.
If ARG is positive goto next line, if negative to previous.
Do nothing when defining or executing kmacros."
  ;; Ensure user enter manually key in minibuffer when recording a macro.
  (unless (or defining-kbd-macro executing-kbd-macro
              (not (get-buffer-window "*Register Preview*" 'visible)))
    (let ((fn (if (> arg 0) #'eobp #'bobp))
          (posfn (if (> arg 0)
                     #'point-min
                     (lambda () (1- (point-max)))))
          str)
      (with-current-buffer "*Register Preview*"
        (let ((ovs (overlays-in (point-min) (point-max)))
              pos)
          (goto-char (if ovs
                         (overlay-start (car ovs))
                         (point-min)))
          (setq pos (point))
          (forward-line (if ovs arg (1- arg)))
          (when (and (funcall fn)
                     (or (> arg 0) (eql pos (point))))
            (goto-char (funcall posfn)))
          (setq str (buffer-substring-no-properties
                     (line-beginning-position) (1+ (line-beginning-position))))
          (remove-overlays)
          (with-selected-window (minibuffer-window)
            (delete-minibuffer-contents)
            (insert str)))))))

(defun register-preview-next (&optional arg)
  "Goto next line in register preview buffer."
  (interactive "p")
  (register-preview-forward-line arg))

(defun register-preview-previous (&optional arg)
  "Goto previous line in register preview buffer."
  (interactive "p")
  (register-preview-forward-line (- arg)))

(defun register-preview-get-type (register)
  "Return REGISTER type.
Current register types actually returned are one of:
- string
- number
- marker
- buffer
- file
- file-query
- window
- frame
- kmacro

One can add new types to a specific command by defining a new `cl-defmethod'
matching this command.  Predicate for type in new `cl-defmethod' should
satisfy `cl-typep' otherwise the new type should be defined with
`cl-deftype'."
  ;; Call register-preview--type against the register value.
  (register-preview--type (if (consp (cdr register))
                     (cadr register)
                   (cdr register))))

(cl-defgeneric register-preview--type (regval)
  "Return type of register value REGVAL."
  (ignore regval))

(cl-defmethod register-preview--type ((_regval string)) 'string)
(cl-defmethod register-preview--type ((_regval number)) 'number)
(cl-defmethod register-preview--type ((_regval marker)) 'marker)
(cl-defmethod register-preview--type ((_regval (eql 'buffer))) 'buffer)
(cl-defmethod register-preview--type ((_regval (eql 'file))) 'file)
(cl-defmethod register-preview--type ((_regval (eql 'file-query))) 'file-query)
(cl-defmethod register-preview--type ((_regval window-configuration)) 'window)
(cl-deftype frame-register () '(satisfies frameset-register-p))
(cl-defmethod register-preview--type :extra "frame-register" (_regval) 'frame)
(cl-deftype kmacro-register () '(satisfies kmacro-register-p))
(cl-defmethod register-preview--type :extra "kmacro-register" (_regval) 'kmacro)

(defun register-preview-filter-alist (types)
  "Filter `register-alist' according to TYPES."
  (if (memq 'all types)
      register-alist
    (cl-loop for register in register-alist
             when (memq (register-preview-get-type register) types)
             collect register)))

(defun register-preview-preview (buffer &optional show-empty types)
  "Pop up a window showing the registers preview in BUFFER.
If SHOW-EMPTY is non-nil, show the window even if no registers.
Argument TYPES (a list) specify the types of register to show, when nil show all
registers, see `register-preview-get-type' for suitable types.
Format of each entry is controlled by the variable `register-preview-function'."
  (let ((registers (register-preview-filter-alist (or types '(all)))))
    (when (or show-empty (consp registers))
      (with-current-buffer-window
        buffer
        (cons 'display-buffer-below-selected
	      '((window-height . fit-window-to-buffer)
	        (preserve-size . (nil . t))))
        nil
        (with-current-buffer standard-output
          (setq cursor-in-non-selected-windows nil)
          (mapc (lambda (elem)
                  (when (get-register (car elem))
                    (insert (funcall register-preview-function elem))))
                registers))))))

(cl-defgeneric register-preview-get-defaults (action)
  "Return default registers according to ACTION."
  (ignore action))
(cl-defmethod register-preview-get-defaults ((_action (eql set)))
  (cl-loop for s in register-preview-default-keys
           unless (assoc (string-to-char s) register-alist)
           collect s))

(defun register-preview--read-with-preview (prompt)
  "Read and return a register name, possibly showing existing registers.
Prompt with the string PROMPT.
If `help-char' (or a member of `help-event-list') is pressed,
display such a window regardless."
  (let* ((buffer "*Register Preview*")
         (pat "")
         (map (let ((m (make-sparse-keymap)))
                (set-keymap-parent m minibuffer-local-map)
                m))
         (data (register-preview-command-info this-command))
         types msg result timer act win strs smatch)
    (if data
        (setq types  (register-preview-info-types data)
              msg    (register-preview-info-msg   data)
              act    (register-preview-info-act   data)
              smatch (register-preview-info-smatch data))
      (setq types '(all)
            msg   "Overwrite register `%s'"
            act   'set))
    (setq strs (mapcar (lambda (x)
                         (string (car x)))
                       (register-preview-filter-alist types)))
    (when (and (memq act '(insert jump view)) (null strs))
      (error "No register suitable for `%s'" act))
    (dolist (k (cons help-char help-event-list))
      (define-key map
          (vector k) (lambda ()
                       (interactive)
                       (unless (get-buffer-window buffer)
                         (with-selected-window (minibuffer-selected-window)
                           (register-preview-preview buffer 'show-empty types))))))
    (define-key map (kbd "<down>") 'register-preview-next)
    (define-key map (kbd "<up>")   'register-preview-previous)
    (define-key map (kbd "C-n")    'register-preview-next)
    (define-key map (kbd "C-p")    'register-preview-previous)
    (unless executing-kbd-macro
      (register-preview-preview buffer nil types))
    (unwind-protect
         (progn
           (minibuffer-with-setup-hook
               (lambda ()
                 (setq timer
                       (run-with-idle-timer
                        0.01 'repeat
                        (lambda ()
                          (with-selected-window (minibuffer-window)
                            (let ((input (minibuffer-contents)))
                              (when (> (length input) 1)
                                (let ((new (substring input 1))
                                      (old (substring input 0 1)))
                                  (setq input (if (or (null smatch)
                                                      (member new strs))
                                                  new old))
                                  (delete-minibuffer-contents)
                                  (insert input)))
                              (when (and smatch (not (string= input ""))
                                         (not (member input strs)))
                                (setq input "")
                                (delete-minibuffer-contents)
                                (minibuffer-message "Not matching"))
                              (when (not (string= input pat))
                                (setq pat input))))
                          (if (setq win (get-buffer-window buffer))
                              (with-selected-window win
                                (let ((ov (make-overlay (point-min) (point-min))))
                                  (goto-char (point-min))
                                  (remove-overlays)
                                  (unless (string= pat "")
                                    (if (re-search-forward (concat "^" pat) nil t)
                                        (progn (move-overlay
                                                ov
                                                (match-beginning 0) (line-end-position))
                                               (overlay-put ov 'face 'match)
                                               (when msg
                                                 (with-selected-window (minibuffer-window)
                                                   (minibuffer-message msg pat))))
                                      (with-selected-window (minibuffer-window)
                                        (minibuffer-message
                                         "Register `%s' is empty" pat))))))
                            (unless (string= pat "")
                              (if (member pat strs)
                                  (with-selected-window (minibuffer-window)
                                    (minibuffer-message msg pat))
                                (with-selected-window (minibuffer-window)
                                  (minibuffer-message
                                   "Register `%s' is empty" pat)))))))))
             (setq result (read-from-minibuffer
                           prompt nil map nil nil (register-preview-get-defaults act))))
           (cl-assert (and result (not (string= result "")))
                      nil "No register specified")
           (string-to-char result))
      (when timer (cancel-timer timer))
      (let ((w (get-buffer-window buffer)))
        (and (window-live-p w) (delete-window w)))
      (and (get-buffer buffer) (kill-buffer buffer)))))

;;;###autoload
(define-minor-mode register-preview-mode
    "Enhanced register preview for all register commands."
  :global t
  (if register-preview-mode
      (advice-add 'register-read-with-preview :override #'register-preview--read-with-preview)
    (advice-remove 'register-read-with-preview #'register-preview--read-with-preview)))


(provide 'register-preview)

;;; register-preview.el ends here

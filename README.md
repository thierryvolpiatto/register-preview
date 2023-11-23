# register-preview
Enhance Emacs vanilla register preview

## Features

- Preview buffer is filtered according to register types.
- Navigation available.
- Default registers are proposed on creation.
- Fully configurable with generics when new register commands are created.

NOTE: `register-read-with-preview` is adviced in this package with `register-preview--read-with-preview`.

## Example

```elisp
    (with-eval-after-load 'register
      (register-preview-mode 1)
      (defun register-delete (register)
        (interactive (list (register-read-with-preview "Delete register: ")))
        (setq register-alist (delete (assoc register register-alist)
                                     register-alist)))
      
      (cl-defmethod register-commands-data ((_command (eql register-delete)))
        (make-register-preview-commands
         :types '(all)
         :msg "Delete register `%s'"
         :act 'delete
         :smatch t)))
```

This enable register-preview and create a new command `register-delete`.

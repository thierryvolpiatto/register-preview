# register-preview
Enhance Emacs vanilla register preview

## Warning

This package provide a feature already provided in Emacs-30+ and by
the way is incompatible with such Emacs versions.

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
      
      (cl-defmethod register-preview-command-info ((_command (eql register-delete)))
        (make-register-preview-info
          :types '(all)
          :msg "Delete register `%s'"
          :act 'modify
          :smatch t)))
```

This enable register-preview and create a new command `register-delete`.
